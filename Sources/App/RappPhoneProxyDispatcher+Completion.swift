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
          #endif
        }
      } else {
        await finishFailure(outcome, operationID: operationID, coordinator: coordinator)
      }
    }

    /// Asks the holder for the PIN again when the card refused the one
    /// entered and the retry floor still allows a verification (RAPP
    /// v26.10.21 §10.2), telling the holder the attempts left.
    internal func askAgainAfterRefusedPin(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async -> RefusedPinStep {
      guard let notice = refusedPinNotice(outcome), let action = action(for: operation.kind)
      else { return .outcomeStands }
      if case .rejected(let rejection) = outcome {
        await applyRejectedCredential(rejection)
      }
      pin1ByOperation.removeValue(forKey: operationID)
      pin2ByOperation.removeValue(forKey: operationID)
      let decision = await ask(
        operationID: operationID, operation: operation, action: action, notice: notice,
        coordinator: coordinator)
      guard await acceptDecision(decision, operationID: operationID, operation: operation) else {
        try? await coordinator.deny(operationID: operationID)
        return .declined
      }
      return .askedAgain
    }

    /// What the holder is told before being asked again, or nil when the
    /// outcome is not a refused PIN the floor lets the phone retry.
    private func refusedPinNotice(_ outcome: RappNfcCardExecutor.Outcome) -> String? {
      switch outcome {
      case .rejected(.credential(let role, let remaining?))
      where role != .puk && remaining.attemptsRemaining >= RetryFloor.minimumAttemptsToProceed:
        CredentialOutcomeMessage.rejection(
          credentialName: CredentialLabels.name(for: role), remaining: remaining)

      case .refusedBeforeCredentialTransmit(.invalidCredential(let role)) where role != .puk:
        CredentialOutcomeMessage.incorrect(credentialName: CredentialLabels.name(for: role))

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
      #endif
      switch outcome {
      case .result:
        await coordinator.close()

      case .rejected(.cardAccessNumber):
        CardCredentialStore.forgetAll()
        try? await coordinator.operationFailed(operationID: operationID)

      case .rejected(.credential(let role, let remaining)):
        // The card refused the PIN and the floor allows no further
        // verification: the remaining attempts are the issuer's.
        await applyRejectedCredential(.credential(role, remaining: remaining))
        await refuseAtRetryFloor(role: role, remaining: remaining)
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

      case .credentialBlocked(let role), .credentialInvalidated(let role),
        .retryFloor(let role, _):
        await refuseAtRetryFloor(role: role, remaining: nil)
        try? await coordinator.retryFloor(operationID: operationID)

      case .invalidCredential:
        try? await coordinator.operationFailed(operationID: operationID)

      case .certificateUnavailable, .keyOrAlgorithmMismatch:
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
      }
    }

    /// Tells the holder that the card's remaining attempts are reserved for
    /// its issuer's software (§10.2).
    private func refuseAtRetryFloor(role: CredentialRole, remaining: RetryCount?) async {
      guard let remaining else {
        await inbox.inform(CredentialOutcomeMessage.lowAttemptRefusal())
        return
      }
      await inbox.inform(
        CredentialOutcomeMessage.lowAttemptRefusal(
          credentialName: CredentialLabels.name(for: role), remaining: remaining))
    }

    private func applyRejectedCredential(_ rejection: RappCardExecutor.Rejection) async {
      switch rejection {
      case .cardAccessNumber:
        CardCredentialStore.forgetAll()

      case .credential(.pin1, _):
        CardCredentialStore.forgetPin1()
        await MainActor.run { ReaderPin1Cache.shared.clear() }

      case .credential(.pin2, _):
        pin2Window.forget()

      case .credential(.puk, _):
        break
      }
    }

    internal func invalid(
      _ operationID: RappOperationIdentifier,
      coordinator: RappConnectionCoordinator
    ) async {
      try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
    }

    internal func cancel(_ operationID: RappOperationIdentifier) async {
      #if DEBUG
        HolderTrace.say("cancel: one operation")
      #endif
      pin1ByOperation.removeValue(forKey: operationID)
      pin2ByOperation.removeValue(forKey: operationID)
      if let requestID = requestIDs.removeValue(forKey: operationID) {
        await inbox.cancel(requestID)
      }
    }
  }
#endif
