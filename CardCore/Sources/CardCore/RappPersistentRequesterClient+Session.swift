// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine

  /// The authenticated exchange the requester runs once its transport has
  /// reached the holder.
  extension RappPersistentRequesterClient {
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-client")
    internal func establish() async {
      do {
        guard let pair = try await resolvedPair() else {
          finish(error: .noSelectedPair)
          return
        }
        #if REFINEID_SLIM_RELAY
          try await establishSlim(pair: pair)
          return
        #endif
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

    #if REFINEID_SLIM_RELAY
      /// Opens a slim session over the selected pairing and asks once.
      private func establishSlim(pair: RappPairRecord) async throws {
        guard let operation else {
          finish(error: .protocolFailure)
          return
        }
        let requestID = UUID()
        guard let request = SignRelayOperation.request(for: operation, requestID: requestID) else {
          finish(error: .unexpectedResult)
          return
        }
        let session = try SignRelaySession(role: .requester, pair: pair, vault: vault)
        let installed = state.withLock { state -> Bool in
          guard state.slimSession == nil, !state.completed else { return false }
          state.slimSession = session
          state.slimRequestID = requestID
          return true
        }
        guard installed else { return }
        pendingSlimRequest.withLock { $0 = try? request.encoded() }
        for frame in try await session.start().send {
          try relay.send(frame)
        }
      }

      /// Drives one frame through the slim session, and answers when the
      /// peer's message is the one this client asked for.
      internal func receiveSlim(_ frame: Data) async {
        guard let session = state.withLock({ $0.slimSession }) else { return }
        let step: SignRelayStep
        do {
          step = try await session.receive(frame)
        } catch {
          finish(error: .transport)
          return
        }
        for outgoing in step.send {
          try? relay.send(outgoing)
        }
        if await session.isEstablished {
          await sendPendingSlimRequest(over: session)
        }
        guard
          let payload = step.payload,
          let answer = try? PersistentRelayMessage.decoded(payload),
          let operation
        else { return }
        guard let response = SignRelayOperation.response(from: answer, for: operation) else {
          finish(error: .unexpectedResult)
          return
        }
        finish(response: response)
      }

      /// Sends the one request this client carries, once the session can.
      private func sendPendingSlimRequest(over session: SignRelaySession) async {
        guard
          let encoded = pendingSlimRequest.withLock({ value -> Data? in
            defer { value = nil }
            return value
          })
        else { return }
        guard let sealed = try? await session.seal(encoded) else {
          finish(error: .transport)
          return
        }
        try? relay.send(sealed)
      }
    #endif

    private func receive(
      _ event: RappConnectionCoordinator.Event,
      from coordinator: RappConnectionCoordinator
    ) async {
      let eventDesc = String(describing: event)
      Self.logger.notice(
        "[RappRequester] coordinator event: \(eventDesc, privacy: .public)"
      )
      switch event {
      case .established:
        await beginOperation(on: coordinator)

      case .progress(_, let progressEvent):
        handleProgress(progressEvent: progressEvent)

      case .completed(_, let result):
        await handleCompleted(result, on: coordinator)

      case .terminal(_, _, let reason):
        await handleTerminal(reason, on: coordinator)

      case .closed(let reason):
        handleClosed(reason)

      case .inspectPrerequisites, .awaitUserApproval, .executeSafeRead,
        .executeCardCommand, .advisoryCancellation, .operationFinished,
        .peerBusy, .peerUnknownOperation:
        Self.logger.notice(
          "[RappRequester] coordinator unexpected proxy event on requester: \(eventDesc, privacy: .public)"
        )
        await coordinator.close()
        finish(error: .protocolFailure)
      }
    }

    private func handleProgress(progressEvent: ProgressEvent) {
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
        Self.logger.notice("[RappRequester] completed with unexpected result")
        finish(error: .unexpectedResult)
      }
    }

    private func handleTerminal(
      _ reason: RappOperationDriver.TerminalReason?,
      on coordinator: RappConnectionCoordinator
    ) async {
      postDistributedNotification(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      Self.logger.notice(
        "[RappRequester] coordinator terminal reason: \(String(describing: reason), privacy: .public)"
      )
      await coordinator.close()
      finish(error: .terminal(reason))
    }

    private func handleClosed(_ reason: RappConnectionCoordinator.CloseReason) {
      postDistributedNotification(RappCardPromptNotificationNames.cardDismissDarwinNotification)
      Self.logger.notice(
        "[RappRequester] coordinator closed: \(String(describing: reason), privacy: .public)"
      )
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
        Self.logger.notice(
          "[RappRequester] beginOperation failed with wrongPhase: \(String(describing: localError), privacy: .public)"
        )
        await coordinator.close()
        finish(error: .transport)
      } catch {
        Self.logger.notice(
          "[RappRequester] beginOperation failed: \(String(describing: error), privacy: .public)"
        )
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
