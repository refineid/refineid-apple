// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
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
        await beginOperation(on: coordinator)

      case .progress(_, let progressEvent):
        RappRequesterNotices.post(progress: progressEvent)

      case .completed(_, let result):
        await handleCompleted(result, on: coordinator)

      case .terminal(_, let reason):
        await handleTerminal(reason, on: coordinator)

      case .closed(let reason):
        handleClosed(reason)

      case .cardStatus, .operationEnded:
        // A one-shot request offers nothing to a local consumer; the
        // registry's held session acts on the custodian's word. An
        // operation that ends with the session is reported by the close.
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
      RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      let response = self.response(for: result)
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
      RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      #if DEBUG
        Self.logger.notice(
          "[RappRequester] coordinator terminal reason: \(String(describing: reason), privacy: .public)"
        )
      #endif
      await coordinator.close()
      finish(error: .terminal(reason))
    }

    private func handleClosed(_ reason: RappConnectionCoordinator.CloseReason) {
      RappRequesterNotices.post(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      if reason.serviceWithdrawn {
        RappRequesterNotices.post(RappServiceNotificationNames.serviceWithdrawnDarwinNotification)
      }
      endPairing(after: reason)
      #if DEBUG
        Self.logger.notice(
          "[RappRequester] coordinator closed: \(String(describing: reason), privacy: .public)"
        )
      #endif
      finish(error: .transport)
    }

    /// Ends the pairing this request ran over when its session said so: the
    /// custodian revoked it, or this endpoint delivered the close of a
    /// pairing it forgot (RAPP v26.10.22 §4.6 items 2 to 4).
    private func endPairing(after reason: RappConnectionCoordinator.CloseReason) {
      let revokedByPeer = reason.peerRevokedPairing
      guard revokedByPeer || reason == .handshake(.revocationNoticeDelivered),
        let pairID = state.withLock({ $0.pairID })
      else { return }
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
      if revokedByPeer {
        RappRequesterNotices.post(RappServiceNotificationNames.pairingRevokedDarwinNotification)
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
        try await dispatchOperation(operation, on: coordinator, lifetime: lifetime)
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

    private func dispatchOperation(
      _ operation: RappRequesterOperation,
      on coordinator: RappConnectionCoordinator,
      lifetime: UInt64
    ) async throws {
      switch operation {
      case .readAuthenticationCertificate:
        try await coordinator.beginReadCertificate(
          signatureCertificate: false,
          expiresAfterMilliseconds: lifetime
        )

      case .readSignatureCertificate:
        try await coordinator.beginReadCertificate(
          signatureCertificate: true,
          expiresAfterMilliseconds: lifetime
        )

      case .browserAuthentication(let context, let keyProfile, let algorithm, let digest):
        try await coordinator.beginBrowserAuthentication(
          origin: context,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          expiresAfterMilliseconds: lifetime
        )

      case .documentSigning(let documentName, let keyProfile, let algorithm, let digest):
        try await coordinator.beginSignDocument(
          documentName: documentName,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          expiresAfterMilliseconds: lifetime
        )
      }
    }

    /// The answer a result carries, when its kind is the one the operation
    /// asked for.
    private func response(for result: RappOperationResult) -> RappRequesterResponse? {
      switch (operation, result) {
      case (.readAuthenticationCertificate, .certificate(let der)):
        der.isEmpty ? nil : .authenticationCertificate(der)

      case (.readSignatureCertificate, .certificate(let der)):
        der.isEmpty ? nil : .signatureCertificate(der)

      case (.browserAuthentication, .signature(let signature)),
        (.documentSigning, .signature(let signature)):
        signature.isEmpty ? nil : .signature(signature)

      default:
        nil
      }
    }
  }
#endif
