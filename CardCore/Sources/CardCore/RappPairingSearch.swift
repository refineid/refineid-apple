// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The requester's tries of one typed pairing code across the custodians
  /// it finds in pairing mode (RAPP v26.10.22 §4.2, "Trying Each Custodian
  /// in Pairing Mode").
  ///
  /// Nothing a custodian advertises tells which one shows the typed code, so
  /// the search tries them in turn. Discovery reports each endpoint it finds
  /// in pairing mode; the search opens one pairing connection at a time,
  /// reads the offer it serves and runs CPace on each `offer_id` at most
  /// once. A refusal, a close, a missing offer, or a CPace step 2 that does
  /// not arrive within the attempt deadline moves on to the next endpoint. A
  /// verified T_B ends the search, and the ceremony continues with that
  /// custodian alone. The code is reported as not accepted only once every
  /// custodian tried refused it, and no report names a custodian (STPA
  /// CC-83, CC-84). A search that tried none tells a custodian it found but
  /// could not reach, and the platform denying the local network, from
  /// finding none in pairing mode; a denial ends it at once. No endpoint is opened while the
  /// requester's remote use is unavailable, off or suspended by a card in
  /// its own reader: the search then ends as interrupted (hierarchy
  /// specification §5.2, STPA CC-102).
  public actor RappPairingSearch<Endpoint: Equatable & Sendable> {
    // MARK: Nested Types

    /// Opens a pairing connection to an endpoint discovery found.
    public typealias Dial = @Sendable (Endpoint) -> RappPairingConnection

    /// Whether the requester's remote use is on and no card is in a reader
    /// attached to it, read whenever an endpoint would be opened.
    public typealias Availability = @Sendable () -> Bool

    /// How one pairing connection ended without its custodian taking the
    /// code; the search moves on.
    public enum Refusal: Sendable, Equatable {
      /// The connection closed, or served no offer in time.
      case noOffer
      /// The connection could not be opened.
      case notOpened(RappPairingConnection.OpenFailure)
      /// The custodian's offer was already tried with this code: the same
      /// custodian, found again.
      case offerAlreadyTried
      /// The offer is not one the requester accepts (Bootstrap Read Flow
      /// item 3).
      case offerRejected
      /// The ceremony ended before the custodian's T_B verified.
      case refused(RappPairingCoordinator.CloseReason)
    }

    /// Why the search ended without a pairing.
    public enum CloseReason: Sendable, Equatable {
      /// A custodian took the code, and the ceremony then ended.
      case ceremonyEnded(RappPairingCoordinator.CloseReason)
      /// Remote use stopped being available during the search: turned off,
      /// or suspended by a card in a reader attached to the requester. The
      /// typed code is dropped and nothing is reported to the user.
      case interrupted
      /// The search was closed locally.
      case localRequest
      /// No custodian found could be reached, and the platform denied this
      /// app the local network for at least one of them.
      case localNetworkDenied
      /// No custodian in pairing mode was tried.
      case noneInPairingMode
      /// Every custodian tried refused the code.
      case notAccepted
      /// Custodians in pairing mode were found, and none could be reached.
      case unreachable
    }

    /// One externally visible event of the search.
    public enum Event: Sendable, Equatable {
      /// The search ended without a pairing; nothing follows.
      case closed(CloseReason)
      /// A custodian did not take the code, and the search moves on.
      case declined(Refusal)
      /// The pairing is stored on both sides; nothing follows.
      case paired(RappPairingCoordinator.PairSummary)
      /// The custodian's authenticated introduction, for naming the pairing.
      case peerIntroduced(RappPairingCoordinator.Peer)
    }

    /// One input the open connection's driver handles, in arrival order.
    internal enum Step: Sendable {
      case ceremony(RappPairingCoordinator.Event)
      case connection(RappPairingConnection.Event)
      case offerOverdue
    }

    /// The pairing connection open now.
    internal struct Attempt {
      /// Tells this connection's inputs from a closed one's.
      internal let generation: Int
      internal let transport: any RappFrameTransport
      /// The driver's input; finishing it stops the driver.
      internal let steps: AsyncStream<Step>.Continuation
      /// The ceremony, once the connection's offer is admitted.
      internal var coordinator: RappPairingCoordinator?
      /// Whether the connection is open and its preamble sent.
      internal var arrived = false
      /// Whether the connection is being closed.
      internal var closing = false
      /// The tasks feeding the driver.
      internal var feeders: [Task<Void, Never>] = []
    }

    // MARK: Properties

    /// Delivers the search's events in order until it ends.
    nonisolated public let events: AsyncStream<Event>

    internal let continuation: AsyncStream<Event>.Continuation
    internal let options: RappPairingCoordinator.Options
    /// The canonical code the user typed.
    internal let code: String
    internal let dial: Dial
    internal let remoteUseAvailable: Availability
    internal let candidates = RappPairingCandidates<Endpoint>()
    internal var attempt: Attempt?
    internal var generation = 0
    /// Whether a custodian's T_B verified.
    internal var codeAccepted = false
    /// Whether any pairing connection opened.
    internal var anyOpened = false
    /// How the connections that could not be opened failed.
    internal var openFailures: Set<RappPairingConnection.OpenFailure> = []
    internal var discoveryEnded = false
    internal var isEnded = false

    // MARK: Computed Properties

    /// Whether the platform denies this app the local network.
    ///
    /// A connection failed for that reason and none opened. No custodian
    /// found later could be reached either, so the search need not wait
    /// for discovery to end.
    internal var localNetworkDenied: Bool {
      !anyOpened && openFailures.contains(.localNetworkDenied)
    }

    /// Why a search that tried no custodian ends: a custodian that opened a
    /// connection and served no offer is not in pairing mode, while one
    /// that could not be reached says nothing of it.
    internal var noneTriedReason: CloseReason {
      if anyOpened || openFailures.isEmpty {
        return .noneInPairingMode
      }
      return localNetworkDenied ? .localNetworkDenied : .unreachable
    }

    // MARK: Lifecycle

    /// The search for the code in `options`, opening connections with
    /// `dial` while `remoteUseAvailable` holds.
    ///
    /// - Throws: ``RappBindingError/InvalidInput`` for a code that is not
    ///   six characters of the code alphabet.
    public init(
      options: RappPairingCoordinator.Options,
      remoteUseAvailable: @escaping Availability,
      dial: @escaping Dial
    ) throws {
      self.code = try RappPairingCoordinator.canonicalCode(options.code)
      self.options = options
      self.remoteUseAvailable = remoteUseAvailable
      self.dial = dial
      (events, continuation) = AsyncStream.makeStream(of: Event.self)
    }

    // MARK: Functions

    /// Records an endpoint discovery found in pairing mode, and opens it
    /// when no pairing connection is open.
    public func found(_ endpoint: Endpoint) async {
      guard !isEnded, !discoveryEnded else { return }
      candidates.found(endpoint)
      await openNext()
    }

    /// Discovery stopped looking.
    ///
    /// Endpoints already found are still tried, and a connection still
    /// being opened runs to its own dialling bound. A search that has tried
    /// no custodian then reports why: none was reachable, or none was in
    /// pairing mode.
    public func endDiscovery() async {
      guard !isEnded, !discoveryEnded else { return }
      discoveryEnded = true
      guard attempt == nil else { return }
      await end(noneTriedReason)
    }

    /// Ends the search at local request, closing any ceremony it runs.
    public func close() async {
      await end(.localRequest)
    }

    /// Ends the search as remote use stops being available, closing the
    /// connection it holds (the state model's `search_interrupted`).
    public func interrupt() async {
      await end(.interrupted)
    }

    /// Ends the search without a pairing.
    internal func end(_ reason: CloseReason) async {
      guard !isEnded else { return }
      isEnded = true
      let current = attempt
      attempt = nil
      continuation.yield(.closed(reason))
      continuation.finish()
      guard let current else { return }
      stop(current)
      await current.coordinator?.close()
      await current.transport.close()
    }

    /// Ends the search with the pairing the ceremony stored.
    internal func finishPaired(_ summary: RappPairingCoordinator.PairSummary) {
      guard !isEnded else { return }
      isEnded = true
      if let current = attempt {
        stop(current)
      }
      attempt = nil
      continuation.yield(.paired(summary))
      continuation.finish()
    }

    /// Stops the tasks feeding a connection's driver, and the driver.
    internal func stop(_ current: Attempt) {
      for feeder in current.feeders {
        feeder.cancel()
      }
      current.steps.finish()
    }

    deinit {
      continuation.finish()
    }
  }
#endif
