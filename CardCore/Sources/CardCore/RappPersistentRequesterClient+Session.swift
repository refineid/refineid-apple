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
        let coordinator = try RappConnectionCoordinator(
          role: .requester,
          pair: pair,
          vault: vault,
          transport: transport,
          maximumLifetimeMilliseconds: policy.maximumOperationLifetimeMilliseconds,
          liveness: policy.liveness
        )
        let installed = state.withLock { state -> Bool in
          guard state.coordinator == nil, !state.completed else { return false }
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

      case .progress(let operationID, let progressEvent):
        handleProgress(operationID: operationID, progressEvent: progressEvent)

      case .completed(_, let result):
        await handleCompleted(result, on: coordinator)

      case .terminal(_, _, let reason):
        await handleTerminal(reason, on: coordinator)

      case .closed(let reason):
        handleClosed(reason)

      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
        .executeCardCommand, .operationFinished,
        .peerBusy, .peerUnknownOperation, .batchSignatures:
        #if DEBUG
          Self.logger.notice(
            "[RappRequester] coordinator unexpected proxy event on requester: \(eventDesc, privacy: .public)"
          )
        #endif
        await coordinator.close()
        finish(error: .protocolFailure)
      }
    }

    private func handleProgress(operationID: Data, progressEvent: ProgressEvent) {
      guard !operationID.isEmpty else { return }
      if progressEvent == .waitingForCard {
        postDistributedNotification(RappCardPromptNotificationNames.cardNeededDarwinNotification)
      } else if progressEvent == .cardWaitEnded {
        postDistributedNotification(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      }
    }

    private func handleCompleted(
      _ result: RappOperationDriver.Result,
      on coordinator: RappConnectionCoordinator
    ) async {
      postDistributedNotification(RappCardPromptNotificationNames.cardDismissDarwinNotification)
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
      _ reason: RappOperationDriver.TerminalReason?,
      on coordinator: RappConnectionCoordinator
    ) async {
      postDistributedNotification(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      #if DEBUG
        Self.logger.notice(
          "[RappRequester] coordinator terminal reason: \(String(describing: reason), privacy: .public)"
        )
      #endif
      await coordinator.close()
      finish(error: .terminal(reason))
    }

    private func handleClosed(_ reason: RappConnectionCoordinator.CloseReason) {
      postDistributedNotification(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      if reason == .operation(.serviceWithdrawn) {
        postDistributedNotification(RappServiceNotificationNames.serviceWithdrawnDarwinNotification)
      }
      #if DEBUG
        Self.logger.notice(
          "[RappRequester] coordinator closed: \(String(describing: reason), privacy: .public)"
        )
      #endif
      finish(error: .transport)
    }

    private func postDistributedNotification(_ name: String) {
      #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
          Notification.Name(name),
          object: nil,
          userInfo: nil,
          deliverImmediately: true
        )
      #endif
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
    private func response(
      for result: RappOperationDriver.Result
    ) -> RappRequesterResponse? {
      switch (operation, result.kind) {
      case (.readAuthenticationCertificate, .certificate):
        result.bytes.isEmpty
          ? nil
          : .authenticationCertificate(result.bytes, cardSerial: result.personID)

      case (.readSignatureCertificate, .certificate):
        result.bytes.isEmpty ? nil : .signatureCertificate(result.bytes)

      case (.browserAuthentication, .signature):
        result.bytes.isEmpty ? nil : .signature(result.bytes)

      case (.documentSigning, .signature):
        result.bytes.isEmpty ? nil : .signature(result.bytes)

      default:
        nil
      }
    }
  }
#endif
