// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  import Network
  import os
  import RappEngine
  /// Single-use synchronous facade for CryptoTokenKit and registry callbacks.
  ///
  /// The blocking boundary contains no protocol logic; an actor-owned RAPP
  /// coordinator performs the authenticated asynchronous exchange.
  public final class RappPersistentRequesterClient: @unchecked Sendable {
    // MARK: Nested Types

    internal struct State: Sendable {
      internal var started = false
      internal var connected = false
      internal var operationStarted = false
      internal var completed = false
      internal var coordinator: RappConnectionCoordinator?
      /// The pairing the session runs over, once it is chosen.
      internal var pairID: Data?
      /// Whether the session was established (RAPP v26.10.29 §4.6 item 5).
      internal var established = false
      internal var response: RappRequesterResponse?
      internal var error: RappRequesterClientError?
    }

    // MARK: Properties

    private let displayName: String
    internal let policy: RappRequesterPolicy
    internal let explicitPairing: PersistentTokenPairing?
    internal let vault: RappDeviceVault
    internal let state = OSAllocatedUnfairLock(initialState: State())
    private let completed = DispatchSemaphore(value: 0)

    /// Frames enter the coordinator in arrival order through this
    /// bounded chain.
    private let frameDelivery = OrderedDelivery(
      capacity: OrderedDelivery.relayFrameCapacity)
    internal var operation: RappRequesterOperation?

    #if REFINEID_STREAM_TRANSPORT
      internal var browser: StreamRelayBrowser?
      internal var dialer: StreamRelaySession?
    #else
      internal lazy var relay = PersistentRelaySession(
        role: .host,
        displayName: displayName
      ) { [weak self] event in
        self?.receive(event)
      }
    #endif

    internal lazy var transport = RappClosureFrameTransport(
      sender: { [weak self] frame in
        guard let self else { throw RappRequesterClientError.transport }
        try await sendOverTransport(frame)
      },
      closer: { [weak self] in
        self?.cancelTransport()
      }
    )

    /// Builds a one-shot client that connects over the persistent relay
    /// and loads its pair from the vault: the one `pairing` names, or the
    /// selected one.
    public init(
      displayName: String,
      policy: RappRequesterPolicy = .interactive,
      pairing: PersistentTokenPairing? = nil,
      vault: RappDeviceVault = RappDeviceVault()
    ) {
      self.displayName = displayName
      self.policy = policy
      self.explicitPairing = pairing
      self.vault = vault
    }

    // MARK: Static Functions

    /// The most recently made pairing, which is the one to use when the
    /// holder has not chosen among several.
    private static func newestPairID(in vault: RappDeviceVault) async throws -> Data? {
      try await RappPairCatalog(vault: vault)
        .activePairs()
        .max { $0.createdAtMilliseconds < $1.createdAtMilliseconds }?
        .pairID
    }

    // MARK: Functions

    /// Runs one operation and blocks the caller until it resolves.
    ///
    /// The wait is bounded by the policy's synchronous timeout. A client
    /// performs at most one operation; a second call fails as a protocol
    /// error.
    public func perform(_ operation: RappRequesterOperation) throws -> RappRequesterResponse {
      let accepted = state.withLock { state -> Bool in
        guard !state.started else { return false }
        state.started = true
        return true
      }
      guard accepted else { throw RappRequesterClientError.protocolFailure }
      self.operation = operation
      startTransport()

      // Discovery has the policy's own deadline. On a screen a device that
      // is not on this network is not slow, it is absent, and waiting the
      // full operation lifetime to say so leaves the holder watching a
      // spinner; a consumer's request against an offered identity instead
      // waits for the custodian as long as the request may (RAPP v26.10.29
      // §8.4 item 3). The first wait consumes the signal, so an answer that
      // arrives inside the discovery window must not be waited for a second
      // time: nothing would ever signal again and a settled request would
      // sit out the whole operation lifetime.
      var settled = completed.wait(timeout: .now() + policy.discoveryTimeout) == .success
      if !settled, !state.withLock({ $0.connected }) {
        state.withLock { state in
          guard !state.completed else { return }
          state.completed = true
          state.error = .peerNotFound
        }
        cancelTransport()
        throw RappRequesterClientError.peerNotFound
      }

      if !settled {
        settled = completed.wait(timeout: .now() + policy.synchronousWaitTimeout) == .success
      }
      guard settled else {
        let coordinator = state.withLock { state -> RappConnectionCoordinator? in
          guard !state.completed else { return state.coordinator }
          state.completed = true
          state.error = .timedOut
          return state.coordinator
        }
        Task { await coordinator?.close() }
        cancelTransport()
        throw RappRequesterClientError.timedOut
      }

      cancelTransport()
      return try state.withLock { state in
        if let response = state.response { return response }
        throw state.error ?? RappRequesterClientError.transport
      }
    }

    // MARK: Lifecycle

    internal func receive(_ event: PersistentRelayEvent) {
      switch event {
      case .connected:
        state.withLock { $0.connected = true }
        deliverInOrder { [weak self] in
          await self?.establish()
        }

      case .frame(let frame):
        deliverInOrder { [weak self] in
          let coordinator = self?.state.withLock { $0.coordinator }
          await coordinator?.receive(frame)
        }

      case .closed:
        deliverInOrder { [weak self] in
          let coordinator = self?.state.withLock { $0.coordinator }
          await coordinator?.transportClosed()
          self?.finish(error: .transport)
        }
      }
    }

    /// Runs `work` after every delivery enqueued before it; a peer that
    /// outruns the bounded chain ends the request as a transport failure.
    private func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      if frameDelivery.deliver(work) { return }
      cancelTransport()
      finish(error: .transport)
    }

    /// The pairing this request runs over, selecting the newest when
    /// several are held and none is chosen.
    ///
    /// Several pairings and none chosen is what a device holds after it
    /// has been paired more than once, and the one the holder made last is
    /// the one they made to use. Refusing here asked for a fresh code the
    /// holder had already scanned.
    internal func resolvedPairID() async throws -> Data? {
      if let explicitPairing {
        return explicitPairing.pairID
      }
      let pairIDs = try vault.activePairIDs()
      guard !pairIDs.isEmpty else { return nil }
      if let selected = try vault.selectedPairID() {
        guard pairIDs.contains(selected) else {
          try vault.clearSelectedPair()
          return nil
        }
        return selected
      }
      if let newest = try await Self.newestPairID(in: vault) {
        try vault.selectPair(pairID: newest)
        return newest
      }
      return nil
    }

    /// The pair record this request runs over, loaded from the vault.
    internal func resolvedPair() async throws -> RappPairRecord? {
      guard let pairID = try await resolvedPairID() else { return nil }
      return try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
    }

    /// Settles the request with the answer the holder gave.
    internal func finish(response: RappRequesterResponse) {
      settle(response: response, error: nil)
    }

    /// Settles the request with the reason it produced no answer.
    internal func finish(error: RappRequesterClientError) {
      settle(response: nil, error: error)
    }

    /// Records the outcome and releases the blocking caller, once.
    private func settle(
      response: RappRequesterResponse?,
      error: RappRequesterClientError?
    ) {
      let shouldSignal = state.withLock { state -> Bool in
        guard !state.completed else { return false }
        state.completed = true
        state.response = response
        state.error = error
        return true
      }
      if shouldSignal { completed.signal() }
    }

  }
#endif
