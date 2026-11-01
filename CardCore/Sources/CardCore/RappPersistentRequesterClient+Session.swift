// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine

  /// The authenticated exchange the requester runs once its transport has
  /// reached the holder.
  extension RappPersistentRequesterClient {
    #if DEBUG
      private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-client")
    #endif
    internal func establish() async {
      do {
        guard let pair = try await resolvedPair() else {
          finish(error: .noSelectedPair)
          return
        }
        let pairID = pair.metadata().pairId
        let coordinator = try RappConnectionCoordinator(
          role: .requester,
          pair: pair,
          transport: transport,
          maximumLifetimeMilliseconds: policy.maximumOperationLifetimeMilliseconds
        )
        let installed = state.withLock { state -> Bool in
          guard state.coordinator == nil, !state.completed else { return false }
          state.coordinator = coordinator
          state.pairID = pairID
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
        finish(error: .protocolFailure)
      }
    }

    private func receive(
      _ event: RappConnectionCoordinator.Event,
      from coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        let eventDesc = String(describing: event)
      #endif
      #if DEBUG
        Self.logger.notice(
          "[RappRequester] coordinator event: \(eventDesc, privacy: .public)"
        )
      #endif
      switch event {
      case .established:
        state.withLock { $0.established = true }
        recordSession()
        await beginOperation(on: coordinator)

      case .progress(_, let progressEvent):
        RappRequesterNotices.post(progress: progressEvent)

      case .completed(_, let result):
        await handleCompleted(result, on: coordinator)

      case .terminal(_, let reason):
        await handleTerminal(reason, on: coordinator)

      case .closed(let reason):
        handleClosed(reason)

      case .cardStatus, .operationEnded, .answered:
        // A one-shot request offers nothing to a local consumer; the
        // registry's held session acts on the custodian's word. An
        // operation that ends with the session is reported by the close,
        // and only a custodian answers an operation.
        break

      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
        .executeCardCommand:
        #if DEBUG
          Self.logger.notice(
            "[RappRequester] coordinator unexpected proxy event on requester: \(eventDesc, privacy: .public)"
          )
        #endif
        await coordinator.close()
        finish(error: .protocolFailure)
      }
    }

    private func handleCompleted(
      _ result: RappOperationResult,
      on coordinator: RappConnectionCoordinator
    ) async {
      RappRequesterNotices.post(RappRequesterNotices.cardWaitEnded)
      let response = operation?.response(for: result)
      await coordinator.close()
      if let response {
        finish(response: response)
      } else {
        #if DEBUG
          Self.logger.notice("[RappRequester] completed with unexpected result")
        #endif
        finish(error: .unexpectedResult)
      }
    }

    private func handleTerminal(
      _ reason: RappTerminalReason,
      on coordinator: RappConnectionCoordinator
    ) async {
      RappRequesterNotices.post(RappRequesterNotices.cardWaitEnded)
      #if DEBUG
        Self.logger.notice(
          "[RappRequester] coordinator terminal reason: \(String(describing: reason), privacy: .public)"
        )
      #endif
      await coordinator.close()
      finish(error: .terminal(reason))
    }

    private func handleClosed(_ reason: RappConnectionCoordinator.CloseReason) {
      if state.withLock({ $0.established }) {
        recordSession()
      }
      RappRequesterNotices.post(RappRequesterNotices.cardWaitEnded)
      if reason.serviceWithdrawn {
        RappRequesterNotices.post(RappRequesterNotices.serviceWithdrawn)
      }
      endPairing(after: reason)
      #if DEBUG
        Self.logger.notice(
          "[RappRequester] coordinator closed: \(String(describing: reason), privacy: .public)"
        )
      #endif
      finish(error: .transport)
    }

    /// Records the session in its pairing's stored record, as it is
    /// established and as it ends, for idle expiry (RAPP v26.10.29 §4.6
    /// item 5).
    private func recordSession() {
      guard let pairID = state.withLock({ $0.pairID }) else { return }
      let recorded = RappPairIdleExpiry.recordSession(
        pairID: pairID, in: vault, nowMilliseconds: RappPlatformClock().wallMilliseconds())
      #if DEBUG
        if !recorded {
          Self.logger.error("[RappRequester] session time not stored")
        }
      #endif
    }

    /// Ends the pairing this request ran over when its session said so: the
    /// custodian revoked it, or this endpoint delivered the close of a
    /// pairing it forgot (RAPP v26.10.29 §4.6 items 2 to 4).
    private func endPairing(after reason: RappConnectionCoordinator.CloseReason) {
      let revokedByPeer = reason.peerRevokedPairing
      guard revokedByPeer || reason == .handshake(.revocationNoticeDelivered),
        let pairID = state.withLock({ $0.pairID })
      else { return }
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
      if revokedByPeer {
        RappRequesterNotices.post(RappRequesterNotices.pairingRevoked)
      }
    }

    /// Asks for the operation this request was made for, once.
    private func beginOperation(on coordinator: RappConnectionCoordinator) async {
      let shouldStart = state.withLock { state -> Bool in
        guard !state.operationStarted, !state.completed else { return false }
        state.operationStarted = true
        return true
      }
      guard shouldStart, let operation else { return }
      let lifetime = policy.maximumOperationLifetimeMilliseconds
      do {
        try await coordinator.begin(operation, lifetime: lifetime)
      } catch let localError as RappOperationDriver.LocalError where localError == .wrongPhase {
        #if DEBUG
          Self.logger.notice(
            "[RappRequester] beginOperation failed with wrongPhase: \(String(describing: localError), privacy: .public)"
          )
        #endif
        await coordinator.close()
        finish(error: .transport)
      } catch {
        #if DEBUG
          Self.logger.notice(
            "[RappRequester] beginOperation failed: \(String(describing: error), privacy: .public)"
          )
        #endif
        await coordinator.close()
        finish(error: .protocolFailure)
      }
    }
  }
#endif
