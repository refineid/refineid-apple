// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// Completion, failure, and cancellation handling for one authenticated
  /// phone-side RAPP connection.
  extension RappPhoneProxyDispatcher {
    /// What follows an outcome that may be a refused PIN.
    internal enum RefusedPinStep {
      /// The holder entered a new PIN for the same operation.
      case askedAgain
      /// The holder declined; the operation has ended.
      case declined
      /// The outcome ends the operation as it stands.
      case outcomeStands
    }

    /// Why the holder is asked for the PIN again for the same operation.
    internal enum PinRequest {
      /// A held PIN 1 could not be spent; the prompt is a first one.
      case afresh
      /// The card refused the PIN entered; the prompt says so.
      case afterRefusal(String)

      /// What the prompt tells the holder beyond the operation.
      internal var notice: String? {
        switch self {
        case .afresh:
          nil

        case .afterRefusal(let notice):
          notice
        }
      }
    }

    internal func finishRead(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      if case .result(let bytes) = outcome {
        try? await coordinator.completeCertificate(operationID: operationID, der: bytes)
      } else {
        await finishFailure(outcome, operationID: operationID, coordinator: coordinator)
      }
    }

    internal func finishSignature(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      if case .result(let signature) = outcome {
        do {
          #if DEBUG
            HolderTrace.say("answering with \(signature.count) bytes")
          #endif
          try await coordinator.completeSignature(
            operationID: operationID,
            signature: signature
          )
          OperationPhaseTrace.mark("result-sent")
          #if DEBUG
            HolderTrace.say("answer accepted")
          #endif
        } catch {
          #if DEBUG
            HolderTrace.say("answer refused: \(String(describing: error))")
            DevErrorLog.report(
              "signature not delivered: \(DevErrorLog.reason(error))", source: .app)
          #endif
        }
      } else {
        await finishFailure(outcome, operationID: operationID, coordinator: coordinator)
      }
    }

    /// Asks the holder for the PIN again when the card refused the one
    /// entered and the retry floor still allows a verification (RAPP
    /// v26.10.22 §10.2), telling the holder the attempts left; or, when a
    /// held PIN 1 could not be spent, asks as on a first prompt.
    internal func askAgainAfterRefusedPin(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async -> RefusedPinStep {
      guard let request = pinRequest(after: outcome), let action = action(for: operation.kind)
      else { return .outcomeStands }
      if case .rejected(let rejection) = outcome {
        await applyRejectedCredential(rejection)
      }
      pin1ByOperation.removeValue(forKey: operationID)
      pin2ByOperation.removeValue(forKey: operationID)
      let decision = await ask(
        operationID: operationID, operation: operation, action: action,
        notice: request.notice, coordinator: coordinator)
      guard acceptDecision(decision, operationID: operationID, operation: operation) else {
        try? await coordinator.deny(operationID: operationID)
        return .declined
      }
      return .askedAgain
    }

    /// Why the holder is asked for the PIN again, or nil when the outcome
    /// ends the operation as it stands.
    private func pinRequest(after outcome: RappNfcCardExecutor.Outcome) -> PinRequest? {
      switch outcome {
      case .rejected(.credential(let role, let remaining?))
      where role != .puk && remaining.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed:
        .afterRefusal(
          CredentialOutcomeMessage.rejection(
            credentialName: CredentialLabels.name(for: role), remaining: remaining))

      case .refusedBeforeCredentialTransmit(.invalidCredential(let role)) where role != .puk:
        .afterRefusal(
          CredentialOutcomeMessage.incorrect(credentialName: CredentialLabels.name(for: role)))

      case .refusedBeforeCredentialTransmit(.heldPin1Unconfirmed):
        .afresh

      default:
        nil
      }
    }

    /// Ends the operation with the result its outcome names (§10.3).
    internal func finishFailure(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        HolderTrace.say("finishFailure: outcome=\(outcome)")
        Self.reportFailure(outcome)
      #endif
      switch outcome {
      case .result:
        await coordinator.close()

      case .rejected(.cardAccessNumber):
        CardCredentialStore.forgetCardAccessNumber()
        try? await coordinator.operationFailed(operationID: operationID)

      case .rejected(.credential(let role, let remaining)):
        // The card refused the PIN and the floor allows no further
        // verification: the remaining attempts are the issuer's.
        await applyRejectedCredential(.credential(role, remaining: remaining))
        await refuseAtRetryFloor(
          role: role,
          verdict: remaining.map { RetryFloor.evaluate(freshReading: $0) } ?? .refuseLowAttempts,
          remaining: remaining)
        try? await coordinator.retryFloor(operationID: operationID)

      case .refusedBeforeCredentialTransmit(let refusal):
        await finishRefusal(refusal, operationID: operationID, coordinator: coordinator)

      case .completionAmbiguous:
        try? await coordinator.cardError(operationID: operationID)
      }
    }

    private func finishRefusal(
      _ refusal: RappCardExecutor.Refusal,
      operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      switch refusal {
      case .cardUnavailable:
        try? await coordinator.cardError(operationID: operationID)

      case .credentialBlocked(let role):
        await refuseAtRetryFloor(role: role, verdict: .refuseBlocked, remaining: nil)
        try? await coordinator.retryFloor(operationID: operationID)

      case .credentialInvalidated(let role):
        await refuseAtRetryFloor(role: role, verdict: .refuseUnreadable, remaining: nil)
        try? await coordinator.retryFloor(operationID: operationID)

      case .retryFloor(let role, let verdict):
        await refuseAtRetryFloor(role: role, verdict: verdict, remaining: nil)
        try? await coordinator.retryFloor(operationID: operationID)

      case .invalidCredential, .heldPin1Unconfirmed:
        try? await coordinator.operationFailed(operationID: operationID)

      case .certificateUnavailable, .keyOrAlgorithmMismatch:
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
      }
    }

    /// Tells the holder which credential the retry floor kept from the card
    /// and how to recover it (§10.2).
    private func refuseAtRetryFloor(
      role: CredentialRole,
      verdict: RetryFloorVerdict,
      remaining: RetryCount?
    ) async {
      await inbox.inform(
        CredentialOutcomeMessage.floorRefusal(
          role: role, verdict: verdict, remaining: remaining))
    }

    private func applyRejectedCredential(_ rejection: RappCardExecutor.Rejection) async {
      switch rejection {
      case .cardAccessNumber:
        CardCredentialStore.forgetCardAccessNumber()

      case .credential(.pin1, _):
        await MainActor.run { HeldPin1.shared.clear() }

      case .credential(.pin2, _), .credential(.puk, _):
        break
      }
    }

    internal func invalid(
      _ operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        DevErrorLog.report("operation answered requestInvalid", source: .app)
      #endif
      try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
    }

    internal func cancel(_ operationID: RappOperationIdentifier) async {
      #if DEBUG
        HolderTrace.say("cancel: one operation")
      #endif
      pin1ByOperation.removeValue(forKey: operationID)
      pin2ByOperation.removeValue(forKey: operationID)
      promptedOperations.remove(operationID)
      if let requestID = requestIDs.removeValue(forKey: operationID) {
        await inbox.cancel(requestID)
      }
    }
  }
#endif
