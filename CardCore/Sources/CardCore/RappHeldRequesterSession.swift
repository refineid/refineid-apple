// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine) && REFINEID_STREAM_TRANSPORT
  import Foundation
  import os
  import RappEngine

  /// The requester's standing session with the custodian (RAPP v26.10.22
  /// §8.3, §8.4): dialled over the stream when the custodian is on the
  /// network and over Bluetooth otherwise, held open so the custodian's
  /// `card.status` reaches the requester, and used for the operations the
  /// requester's own processes need.
  ///
  /// Reports arrive on the transport's queues; the owner hops to its own.
  public final class RappHeldRequesterSession: @unchecked Sendable {
    // MARK: Nested Types

    /// How the session reaches the custodian.
    public enum Route: Sendable, Equatable {
      /// Browse for the custodian's session record and dial its listener.
      case stream
      /// Scan for the RAPP service and dial one of `peers` over GATT.
      case bluetooth(RappBleCentralPeers)

      /// The transport profile the session binds (§2.2).
      internal var transportProfile: String {
        switch self {
        case .stream:
          rappStreamProfileName()

        case .bluetooth:
          RappBleGattProfile.name
        }
      }
    }

    /// What the session tells its owner.
    public enum Report: Sendable, Equatable {
      /// The Noise session is up; the custodian's first `card.status`
      /// follows.
      case established
      /// The custodian's word on which card it can serve now.
      case cardStatus(RappCardStatus)
      /// The Bluetooth link went to this advertiser, which routed the
      /// preamble or refused it.
      case bluetoothPeer(UUID, routed: Bool)
      /// One step of the Bluetooth link, for a development trace.
      case bluetoothTrace(RappBleGattTrace)
      /// The session ended; the owner decides whether to dial again.
      case closed(RappConnectionCoordinator.CloseReason)
    }

    /// Why an operation over the session produced no answer.
    public enum OperationError: Error, Equatable {
      case notEstablished
      case operationInFlight
      case terminal(RappTerminalReason)
      case closed
      case unexpectedResult
    }

    internal struct State: Sendable {
      internal var coordinator: RappConnectionCoordinator?
      internal var connected = false
      internal var established = false
      internal var finished = false
      internal var bluetoothPeer: UUID?
      internal var pending: CheckedContinuation<RappOperationResult, any Error>?
      internal var awaitingEstablishment: [UUID: CheckedContinuation<Bool, Never>] = [:]
    }

    // MARK: Properties

    internal let pair: RappPairRecord
    internal let route: Route
    internal let policy: RappRequesterPolicy
    internal let report: @Sendable (Report) -> Void
    internal let state = OSAllocatedUnfairLock(initialState: State())
    internal let frameDelivery = OrderedDelivery(capacity: OrderedDelivery.relayFrameCapacity)
    internal let link = Link()
    internal let transport: RappClosureFrameTransport

    /// The pairing the session runs over.
    public var pairID: Data { pair.metadata().pairId }

    /// Whether the session runs over Bluetooth.
    public var isBluetooth: Bool {
      if case .bluetooth = route { return true }
      return false
    }

    // MARK: Lifecycle

    /// Prepares a session over `pair` along `route`; ``start()`` dials.
    @preconcurrency
    public init(
      pair: RappPairRecord,
      route: Route = .stream,
      policy: RappRequesterPolicy = .interactive,
      report: @escaping @Sendable (Report) -> Void
    ) {
      self.pair = pair
      self.route = route
      self.policy = policy
      self.report = report
      let owned = link
      self.transport = RappClosureFrameTransport(
        sender: { frame in try await owned.send(frame) },
        closer: { owned.cancel() })
    }

    // MARK: Static Functions

    /// Resumes the waiting operation, if one is waiting; the lock, not the
    /// session, is what the resumption needs.
    internal static func settle(
      _ state: OSAllocatedUnfairLock<State>, _ outcome: Result<RappOperationResult, any Error>
    ) {
      let waiting = state.withLock {
        state -> CheckedContinuation<RappOperationResult, any Error>? in
        let pending = state.pending
        state.pending = nil
        return pending
      }
      waiting?.resume(with: outcome)
    }

    /// Answers everyone waiting for the session to come up.
    internal static func settleEstablishment(
      _ state: OSAllocatedUnfairLock<State>, _ established: Bool
    ) {
      let waiting = state.withLock { state -> [CheckedContinuation<Bool, Never>] in
        let waiting = Array(state.awaitingEstablishment.values)
        state.awaitingEstablishment.removeAll()
        return waiting
      }
      for continuation in waiting {
        continuation.resume(returning: established)
      }
    }

    // MARK: Functions

    /// Dials along the route; a custodian not reached within the policy's
    /// discovery window ends the session as a transport failure.
    public func start() {
      switch route {
      case .stream:
        startStream()

      case .bluetooth(let peers):
        startBluetooth(peers)
      }
      let discoveryTimeout = policy.discoveryTimeout
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(discoveryTimeout))
        guard let self, !state.withLock({ $0.connected }) else { return }
        finish(.transportFailure)
      }
    }

    /// Whether the session is up within `limit`; false once it ended.
    public func established(within limit: Duration) async -> Bool {
      let ticket = UUID()
      let shared = state
      return await withCheckedContinuation { continuation in
        let settled = shared.withLock { held -> Bool in
          guard !held.established, !held.finished else { return true }
          held.awaitingEstablishment[ticket] = continuation
          return false
        }
        guard !settled else {
          continuation.resume(returning: shared.withLock { $0.established })
          return
        }
        Task {
          try? await Task.sleep(for: limit)
          let waiting = shared.withLock { $0.awaitingEstablishment.removeValue(forKey: ticket) }
          waiting?.resume(returning: false)
        }
      }
    }

    /// Reads the custodian's authentication certificate over the session.
    public func readAuthenticationCertificate() async throws -> Data {
      guard
        case .authenticationCertificate(let der) = try await perform(
          .readAuthenticationCertificate)
      else { throw OperationError.unexpectedResult }
      return der
    }

    /// Runs one operation over the session and answers what it yields.
    ///
    /// One operation at a time; the session must be established.
    public func perform(_ operation: RappRequesterOperation) async throws
      -> RappRequesterResponse
    {
      let lifetime = policy.maximumOperationLifetimeMilliseconds
      let shared = state
      let result = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<RappOperationResult, any Error>) in
        let armed: Result<RappConnectionCoordinator, OperationError> = shared.withLock { held in
          guard !held.finished else { return .failure(.closed) }
          guard held.established, let coordinator = held.coordinator else {
            return .failure(.notEstablished)
          }
          guard held.pending == nil else { return .failure(.operationInFlight) }
          held.pending = continuation
          return .success(coordinator)
        }
        switch armed {
        case .failure(let refusal):
          continuation.resume(throwing: refusal)

        case .success(let coordinator):
          Task {
            do {
              try await coordinator.begin(operation, lifetime: lifetime)
            } catch {
              Self.settle(shared, .failure(OperationError.unexpectedResult))
            }
          }
        }
      }
      guard let response = operation.response(for: result) else {
        throw OperationError.unexpectedResult
      }
      return response
    }

    /// Ends the session with a plain close, after the frames in flight.
    public func close() {
      let coordinator = state.withLock { $0.coordinator }
      Task { [weak self] in
        await coordinator?.close()
        self?.finish(.localRequest)
      }
    }

    /// Ends the session with `pairing_revoked`, as the pairing it runs over
    /// is forgotten (RAPP v26.10.22 §4.6 item 1).
    ///
    /// The close frame is sent before the connection goes; the answer says
    /// whether it left.
    public func closePairingRevoked() async -> Bool {
      let coordinator = state.withLock { $0.coordinator }
      let told = await coordinator?.closePairingRevoked() ?? false
      finish(.localRequest)
      return told
    }

    /// Reports the end once and releases the transport.
    internal func finish(_ reason: RappConnectionCoordinator.CloseReason) {
      let first = state.withLock { state -> Bool in
        guard !state.finished else { return false }
        state.finished = true
        state.established = false
        return true
      }
      guard first else { return }
      Self.settle(state, .failure(OperationError.closed))
      Self.settleEstablishment(state, false)
      link.cancel()
      report(.closed(reason))
    }

    deinit {
      Self.settle(state, .failure(OperationError.closed))
      Self.settleEstablishment(state, false)
    }
  }
#endif
