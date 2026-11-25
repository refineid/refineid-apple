// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation

  /// Card inspection, command submission, and failure mapping for
  /// ``WebEidPromptModel``.
  extension WebEidPromptModel {
    internal func submit() {
      guard canSubmit, case .ready(let preview) = cardState else { return }
      guard Date() < expiresAt else {
        expireTimeout()
        return
      }
      let enteredPin = pinDigits
      pinDigits = ""
      errorMessage = nil
      isSubmitting = true
      activeTask?.cancel()
      activeTask = Task { [weak self] in
        guard let self else { return }
        let result = await runCommand(preview: preview, pin: enteredPin)
        isSubmitting = false
        if let deferredError = deferredTerminationError {
          deferredTerminationError = nil
          finish(.failure(deferredError))
          return
        }
        guard Date() < expiresAt else {
          expireTimeout()
          return
        }
        handleExecutionResult(result)
      }
    }

    internal func applyInspection(_ result: Result<WebEidCardPreview, WebEidCardFailure>) {
      switch result {
      case .success(let preview):
        cardState = .ready(preview)
        applyPreflightChecks(preview)

      case .failure(.noCard):
        cardState = .waitingForCard

      case .failure(.certificateUnavailable):
        isOperationBlocked = true
        cardState = .unavailable(
          String(localized: "No suitable certificate was found on the card.")
        )

      case .failure:
        isOperationBlocked = true
        cardState = .unavailable(String(localized: "Could not read the card."))
      }
    }

    private func applyPreflightChecks(_ preview: WebEidCardPreview) {
      if !preview.certificateMatchesExpected {
        isOperationBlocked = true
        errorMessage = String(localized: "Insert the card selected for signing.")
        return
      }
      if preview.pin2RequiresChangeBeforeSigning, requiredRole == .pin2 {
        isOperationBlocked = true
        errorMessage = String(localized: "Change PIN 2 to sign documents.")
        return
      }
      guard let role = requiredRole else { return }
      if case .locked = preview.retryProbe {
        isOperationBlocked = true
        errorMessage = CredentialOutcomeMessage.blocked(role)
        return
      }
      if preview.retryFloorVerdict != .proceed {
        let remaining: RetryCount? =
          if case .remaining(let count) = preview.retryProbe { count } else { nil }
        isOperationBlocked = true
        errorMessage = CredentialOutcomeMessage.floorRefusal(
          role: role,
          verdict: preview.retryFloorVerdict,
          remaining: remaining
        )
      }
    }

    private func runCommand(
      preview: WebEidCardPreview,
      pin: String
    ) async -> Result<WebEidResponsePayload, WebEidCardFailure> {
      let identity = WebEidCardRunner.ExpectedCardIdentity(
        chipSerial: preview.chipSerial,
        certificateDER: preview.certificateDER
      )
      switch command {
      case .authenticate(let origin, let challengeNonce, _):
        return await WebEidCardRunner.executeAuthenticate(
          origin: origin,
          challengeNonce: challengeNonce,
          pin1: pin,
          expectedIdentity: identity
        )

      case .getSigningCertificate:
        return await WebEidCardRunner.executeGetSigningCertificate(
          expectedIdentity: identity
        )

      case .sign(let request):
        return await WebEidCardRunner.executeSign(
          request: request,
          pin2: pin,
          expectedChipSerial: preview.chipSerial
        )

      case .status:
        return .failure(.cardError)
      }
    }

    private func handleExecutionResult(_ result: Result<WebEidResponsePayload, WebEidCardFailure>) {
      switch result {
      case .success(let payload):
        finish(.success(payload))

      case .failure(let failure):
        applyExecutionFailure(failure)
      }
    }

    private func applyExecutionFailure(_ failure: WebEidCardFailure) {
      let role = requiredRole ?? .pin1
      switch failure {
      case .pinRejected(let remaining):
        let presented: PresentedCredential = role == .pin2 ? .pin2 : .pin1
        if RetryFloor.evaluate(freshReading: remaining) == .proceed {
          errorMessage = CredentialOutcomeMessage.rejection(presented, remaining: remaining)
        } else {
          isOperationBlocked = true
          errorMessage = CredentialOutcomeMessage.floorRefusal(
            role: role,
            verdict: .refuseLowAttempts,
            remaining: remaining
          )
        }

      case .pinBlocked:
        isOperationBlocked = true
        errorMessage = CredentialOutcomeMessage.blocked(role)

      case .retryFloorRefused(let verdict, let remaining):
        isOperationBlocked = true
        errorMessage = CredentialOutcomeMessage.floorRefusal(
          role: role,
          verdict: verdict,
          remaining: remaining
        )

      case .pin2RequiresChangeBeforeSigning:
        isOperationBlocked = true
        errorMessage = String(localized: "Change PIN 2 to sign documents.")

      case .certificateMismatch:
        reloadCard()

      case .noCard:
        cardState = .waitingForCard

      case .invalidPinEntry:
        errorMessage = String(localized: "Check the PIN length and try again.")

      case .invalidated:
        isOperationBlocked = true
        errorMessage = String(localized: "The credential on the card is invalidated.")

      case .unsupportedAlgorithm, .certificateUnavailable, .cardError:
        finish(
          .failure(
            WebEidError(code: .nativeFatal, message: "Card operation failed")
          )
        )
      }
    }
  }

#endif
