// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// Completion, failure, and cancellation handling for one authenticated
  /// phone-side RAPP connection.
  extension RappPhoneProxyDispatcher {
    /// The attempts a rejected credential still has, when the card reported
    /// a count above zero.
    internal static func attemptsLeft(after rejection: RappCardExecutor.Rejection) -> UInt8? {
      guard case .credential(_, let remaining?) = rejection, !remaining.isBlocked else {
        return nil
      }
      return remaining.attemptsRemaining
    }

    internal func finishRead(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      if case .result(let bytes) = outcome {
        let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
        try? await coordinator.completeCertificate(
          operationID: operationID,
          der: bytes,
          cardSerial: isReader ? nil : Self.storedTokenSerial()
        )
      } else {
        await finishFailure(outcome, operationID: operationID, coordinator: coordinator)
      }
    }

    internal func finishSignature(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: Data,
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

    internal func finishFailure(
      _ outcome: RappNfcCardExecutor.Outcome,
      operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        HolderTrace.say("finishFailure: outcome=\(outcome)")
      #endif
      switch outcome {
      case .result:
        await coordinator.close()

      case .rejected(let rejection):
        await applyRejectedCredential(rejection)
        // A mistyped PIN with attempts left keeps the session and the
        // pairing (RAPP v26.10.1 section 10.2); a blocked or uncounted
        // rejection revokes them.
        if let remaining = Self.attemptsLeft(after: rejection) {
          try? await coordinator.invalidCredential(
            operationID: operationID, remainingRetries: remaining)
        } else {
          await requireExplicitReconnect()
          try? await coordinator.credentialRejected(operationID: operationID)
        }

      case .refusedBeforeCredentialTransmit(let refusal):
        switch refusal {
        case .cardUnavailable:
          try? await coordinator.cardRemovedBeforeTransmit(operationID: operationID)

        case .credentialBlocked, .credentialInvalidated, .retryFloor:
          try? await coordinator.retryRefused(operationID: operationID)

        case .certificateUnavailable, .invalidCredential,
          .keyOrAlgorithmMismatch:
          try? await coordinator.requestInvalidOrUnsupported(
            operationID: operationID)
        }

      case .completionAmbiguous:
        await requireExplicitReconnect()
        try? await coordinator.cardCompletionAmbiguous(operationID: operationID)
      }
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
      _ operationID: Data,
      coordinator: RappConnectionCoordinator
    ) async {
      try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
    }

    internal func cancel(_ operationID: Data?) async {
      #if DEBUG
        HolderTrace.say("cancel: operationID=\(operationID?.base64EncodedString() ?? "all")")
      #endif
      guard let operationID else {
        pin1ByOperation.removeAll(keepingCapacity: false)
        pin2ByOperation.removeAll(keepingCapacity: false)
        pin2Window.forget()
        await inbox.cancelAll()
        return
      }
      pin1ByOperation.removeValue(forKey: operationID)
      pin2ByOperation.removeValue(forKey: operationID)
      await inbox.cancel(operationID.base64EncodedString())
    }

    internal func attempts(_ outcome: RetryProbeOutcome?) -> UInt8? {
      switch outcome {
      case .remaining(let count):
        count.attemptsRemaining

      case .locked:
        0

      case .invalidated, .noInformation, .other, .verified, nil:
        nil
      }
    }
  }
#endif
