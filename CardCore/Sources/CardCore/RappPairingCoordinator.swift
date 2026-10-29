// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Drives one RAPP v26.10.29 pairing ceremony over one transport.
  ///
  /// The custodian creates a random offer, shows a pairing code and waits;
  /// the requester's side starts from the offer one connection served
  /// through the transport's bootstrap, with the code its user typed
  /// (``RappPairingSearch`` reads it). CPace KC2 proves both hold the code,
  /// Noise_XXpsk3 binds fresh pair keys, and the custodian grants the
  /// requested profiles without a separate approval: entering the code is
  /// the authorization. The engine owns every secret; this actor moves
  /// frames and reports progress.
  public actor RappPairingCoordinator {
    // MARK: Nested Types

    /// Authenticated peer facts shown for the explicit pairing decision.
    public struct Peer: Sendable, Equatable {
      // MARK: Properties

      /// User-visible peer label shown during pairing confirmation.
      public let displayName: String
      /// Peer platform label.
      public let platform: String
      /// Exact requester profile list; absent when the peer is the proxy.
      public let requestedProfiles: [String]?
      // swiftlint:disable:previous discouraged_optional_collection

      // MARK: Lifecycle

      internal init(_ hello: RappPeerHello) {
        displayName = hello.displayName
        platform = hello.platform
        requestedProfiles = hello.requestedProfiles
      }
    }

    /// Local endpoint role, driven during pairing and bound into the pair record.
    public enum Role: Sendable, Equatable {
      case requester
      case proxy
    }

    /// Non-secret metadata for a completed pairing.
    public struct PairSummary: Sendable, Equatable {
      // MARK: Properties

      /// Transcript-derived pair identifier.
      public let pairID: Data
      /// Local role permanently bound into the pair record.
      public let role: Role
      /// Exact mutually confirmed profile names.
      public let profiles: [String]
      /// Transport profile bound into the pair.
      public let transportProfile: String
      /// Transport candidate identifier bound into the pair.
      public let candidateID: String
      /// Wall-clock creation time recorded in the pair record.
      public let createdAtMilliseconds: UInt64

      // MARK: Lifecycle

      internal init(_ metadata: RappPairMetadata) {
        pairID = metadata.pairId
        role = metadata.role == .requester ? .requester : .proxy
        profiles = metadata.profiles
        transportProfile = metadata.transportProfile
        candidateID = metadata.candidateId
        createdAtMilliseconds = metadata.createdAtMs
      }
    }

    /// Reason the pairing attempt ended without a completed pair.
    public enum CloseReason: Sendable, Equatable {
      case localRequest
      case transportFailure
      case protocolFailure
      case persistenceFailure
      case offerExpired
      /// No CPace step 2 arrived within the attempt deadline of the
      /// requester's step 1 (RAPP v26.10.29 §3.3 item 3).
      case attemptTimedOut
      /// The peer never confirmed storing the pairing; the record this
      /// endpoint stored is revoked (RAPP v26.10.29 §4.3 item 4).
      case storageUnconfirmed
    }

    /// One externally visible pairing event.
    public enum Event: Sendable, Equatable {
      /// A custodian attempt failed and the same offer awaits a new
      /// connection; the transport must be replaced before it can answer.
      case offerRestored
      /// The custodian's T_B verified: it holds the code the requester's
      /// user typed (RAPP v26.10.29 §6.1.3 step 3).
      case keyConfirmed
      /// The peer's authenticated introduction, for naming the pairing.
      case peerIntroduced(Peer)
      case paired(PairSummary)
      case closed(CloseReason)
    }

    internal enum State: Equatable {
      case offer
      case requesterAwaitingStepTwo
      case requesterAwaitingHandshakeTwo
      case custodianAwaitingStepOne
      case custodianAwaitingStepThree
      case custodianAwaitingHandshakeOne
      case custodianAwaitingHandshakeThree
      case awaitingPeerHello
      case awaitingPeerConfirmation
      /// The record is stored and `pairing.stored` sent; the peer's is
      /// awaited (RAPP v26.10.29 §4.3 item 4).
      case awaitingPeerStored
      case completed
      case closed
    }

    // MARK: Properties

    /// Delivers pairing events in order until the attempt ends.
    nonisolated public let events: AsyncStream<Event>

    internal let role: Role
    /// The ceremony's engine.
    internal let bridge: RappPairingBridge
    internal let vault: RappDeviceVault
    internal var transport: any RappFrameTransport
    /// The transport profile this ceremony runs over (RAPP v26.10.29 §2.2).
    internal let transportProfile: String
    internal let candidateID: String
    internal let profiles: [String]
    internal let displayName: String
    internal let platform: String
    internal let clock: RappPlatformClock
    internal let entropy: RappPlatformEntropy
    internal let offerDeadlineMilliseconds: UInt64
    internal let preAuthentication = RappPreAuthenticationLimiter()
    internal let continuation: AsyncStream<Event>.Continuation
    internal var state = State.offer
    internal var deadlineTask: Task<Void, Never>?
    /// The pairing stored before the peer confirmed it; revoked if the
    /// ceremony ends without that confirmation.
    internal var storedPairID: Data?

    // MARK: Lifecycle

    internal init(
      role: Role,
      bridge: RappPairingBridge,
      transportProfile: String,
      candidateID: String,
      profiles: [String],
      displayName: String,
      platform: String,
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      clock: RappPlatformClock,
      entropy: RappPlatformEntropy,
      offerDeadlineMilliseconds: UInt64
    ) {
      self.role = role
      self.bridge = bridge
      self.transportProfile = transportProfile
      self.candidateID = candidateID
      self.profiles = profiles
      self.displayName = displayName
      self.platform = platform
      self.vault = vault
      self.transport = transport
      self.clock = clock
      self.entropy = entropy
      self.offerDeadlineMilliseconds = offerDeadlineMilliseconds

      var capturedContinuation: AsyncStream<Event>.Continuation?
      self.events = AsyncStream { capturedContinuation = $0 }
      guard let capturedContinuation else {
        preconditionFailure("AsyncStream did not provide a continuation")
      }
      self.continuation = capturedContinuation
    }

    deinit {
      deadlineTask?.cancel()
      continuation.finish()
    }
  }
#endif
