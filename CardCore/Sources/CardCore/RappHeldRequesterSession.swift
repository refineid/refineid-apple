// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine) && REFINEID_STREAM_TRANSPORT
  import Foundation
  import Network
  import os
  import RappEngine

  /// The requester's standing session with the custodian (RAPP v26.10.18
  /// §8.4): dialled when the custodian is on the network, held open so the
  /// custodian's `card.status` reaches the requester, and used for the
  /// certificate read that an offered identity needs.
  ///
  /// Reports arrive on the transport's queues; the owner hops to its own.
  public final class RappHeldRequesterSession: @unchecked Sendable {
    // MARK: Nested Types

    /// The certificate a read produced, with the card's serial when known.
    public typealias ReadAnswer = (certificate: Data, cardSerial: String?)

    /// What the session tells its owner.
    public enum Report: Sendable, Equatable {
      /// The Noise session is up; the custodian's first `card.status`
      /// follows.
      case established
      /// The custodian's word on whether a card it can serve is present.
      case cardStatus(present: Bool)
      /// The session ended; the owner decides whether to dial again.
      case closed(RappConnectionCoordinator.CloseReason)
    }

    /// Why a certificate read over the session produced no certificate.
    public enum ReadError: Error, Equatable {
      case notEstablished
      case readInFlight
      case peerBusy
      case terminal(RappOperationDriver.TerminalReason?)
      case closed
      case unexpectedResult
    }

    private struct State: Sendable {
      var coordinator: RappConnectionCoordinator?
      var dialer: StreamRelaySession?
      var connected = false
      var finished = false
      var read: CheckedContinuation<ReadAnswer, any Error>?
    }

    // MARK: Properties

    private let pair: RappPairRecord
    private let vault: RappDeviceVault
    private let policy: RappRequesterPolicy
    private let report: @Sendable (Report) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let frameDelivery = OrderedDelivery(capacity: OrderedDelivery.relayFrameCapacity)
    private let browser = OSAllocatedUnfairLock<StreamRelayBrowser?>(initialState: nil)
    private lazy var transport = RappClosureFrameTransport(
      sender: { [weak self] frame in
        guard let self, let dialer = state.withLock({ $0.dialer }) else {
          throw RappRequesterClientError.transport
        }
        try await dialer.send(frame)
      },
      closer: { [weak self] in
        self?.cancelTransport()
      }
    )

    /// The pairing the session runs over.
    public var pairID: Data { pair.metadata().pairId }

    // MARK: Lifecycle

    /// Prepares a session over `pair`; ``start()`` browses and dials.
    @preconcurrency
    public init(
      pair: RappPairRecord,
      vault: RappDeviceVault = RappDeviceVault(),
      policy: RappRequesterPolicy = .interactive,
      report: @escaping @Sendable (Report) -> Void
    ) {
      self.pair = pair
      self.vault = vault
      self.policy = policy
      self.report = report
    }

    // MARK: Functions

    /// Browses for the custodian's session record and dials it; a
    /// custodian not found within the policy's discovery window ends the
    /// session as a transport failure.
    public func start() {
      let followed = pair
      let found = StreamRelayBrowser(
        matchingRecord: { record in
          StreamRendezvousName.sessionRecord(record, holds: followed, at: Date())
        },
        onFound: { [weak self] endpoint in
          self?.dial(endpoint)
        })
      browser.withLock { $0 = found }
      found.start()
      let discoveryTimeout = policy.discoveryTimeout
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(discoveryTimeout))
        guard let self, !state.withLock({ $0.connected }) else { return }
        finish(.transportFailure)
      }
    }

    /// Reads the custodian's authentication certificate over the session.
    ///
    /// One read at a time; the session must be established.
    public func readAuthenticationCertificate() async throws -> ReadAnswer {
      let coordinator = try state.withLock { state -> RappConnectionCoordinator in
        guard let coordinator = state.coordinator, !state.finished else {
          throw ReadError.notEstablished
        }
        guard state.read == nil else { throw ReadError.readInFlight }
        return coordinator
      }
      let lifetime = policy.maximumOperationLifetimeMilliseconds
      return try await withCheckedThrowingContinuation { continuation in
        let armed = state.withLock { state -> Bool in
          guard state.read == nil, !state.finished else { return false }
          state.read = continuation
          return true
        }
        guard armed else {
          continuation.resume(throwing: ReadError.closed)
          return
        }
        Task { [weak self] in
          do {
            try await coordinator.beginReadCertificate(
              signatureCertificate: false, expiresAfterMilliseconds: lifetime)
          } catch {
            self?.settleRead(.failure(ReadError.unexpectedResult))
          }
        }
      }
    }

    /// Ends the session with a plain close.
    public func close() {
      let coordinator = state.withLock { $0.coordinator }
      Task { [weak self] in
        await coordinator?.close()
        self?.finish(.localRequest)
      }
    }

    /// Ends the session with `pairing_revoked`, before the pairing it
    /// runs over is forgotten (RAPP v26.10.18 §4.6 item 1).
    public func closePairingRevoked() async {
      let coordinator = state.withLock { $0.coordinator }
      await coordinator?.closePairingRevoked()
      finish(.localRequest)
    }

    private func dial(_ endpoint: NWEndpoint) {
      guard
        let preamble = try? pair.sessionPreamble(transportProfile: rappStreamProfileName())
      else {
        finish(.transportFailure)
        return
      }
      let made = StreamRelaySession(service: endpoint, preamble: preamble) { [weak self] event in
        self?.receive(PersistentRelayEvent(event))
      }
      let installed = state.withLock { state -> Bool in
        guard state.dialer == nil, !state.finished else { return false }
        state.dialer = made
        return true
      }
      guard installed else { return }
      made.start()
    }

    private func receive(_ event: PersistentRelayEvent) {
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
          self?.finish(.transportFailure)
        }
      }
    }

    private func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      if frameDelivery.deliver(work) { return }
      finish(.transportFailure)
    }

    private func establish() async {
      do {
        let coordinator = try RappConnectionCoordinator(
          role: .requester,
          pair: pair,
          vault: vault,
          transport: transport,
          maximumLifetimeMilliseconds: policy.maximumOperationLifetimeMilliseconds,
          liveness: policy.liveness
        )
        let installed = state.withLock { state -> Bool in
          guard state.coordinator == nil, !state.finished else { return false }
          state.coordinator = coordinator
          return true
        }
        guard installed else { return }
        Task { [weak self] in
          for await event in coordinator.events {
            await self?.receive(event, from: coordinator)
          }
        }
        await coordinator.start()
      } catch {
        finish(.handshake(.protocolFailure))
      }
    }

    private func receive(
      _ event: RappConnectionCoordinator.Event, from coordinator: RappConnectionCoordinator
    ) async {
      switch event {
      case .established:
        report(.established)

      case .cardStatus(let present):
        report(.cardStatus(present: present))

      case .progress(_, let progressEvent):
        RappRequesterNotices.post(progress: progressEvent)

      case .completed(_, let result):
        RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
        settleRead(certificate(in: result))

      case .terminal(_, _, let reason):
        RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
        settleRead(.failure(ReadError.terminal(reason)))

      case .peerBusy:
        settleRead(.failure(ReadError.peerBusy))

      case .operationFinished, .peerUnknownOperation, .batchSignatures:
        settleRead(.failure(ReadError.unexpectedResult))

      case .closed(let reason):
        RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
        finish(reason)

      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead, .executeCardCommand:
        await coordinator.close()
        finish(.operation(.protocolFailure))
      }
    }

    private func certificate(
      in result: RappOperationDriver.Result
    ) -> Result<ReadAnswer, any Error> {
      guard result.kind == .certificate, !result.bytes.isEmpty else {
        return .failure(ReadError.unexpectedResult)
      }
      return .success((result.bytes, result.personID))
    }

    private func settleRead(_ outcome: Result<ReadAnswer, any Error>) {
      let waiting = state.withLock { state -> CheckedContinuation<ReadAnswer, any Error>? in
        let read = state.read
        state.read = nil
        return read
      }
      waiting?.resume(with: outcome)
    }

    /// Reports the end once and releases the transport.
    private func finish(_ reason: RappConnectionCoordinator.CloseReason) {
      let first = state.withLock { state -> Bool in
        guard !state.finished else { return false }
        state.finished = true
        return true
      }
      guard first else { return }
      settleRead(.failure(ReadError.closed))
      cancelTransport()
      report(.closed(reason))
    }

    private func cancelTransport() {
      browser.withLock { $0?.cancel() }
      state.withLock { $0.dialer }?.cancel()
    }
  }
#endif
