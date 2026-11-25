// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation

  /// Interactive inspect -> native `NSAlert` -> execute ceremony loop for
  /// ``WebEidCoordinator``.
  extension WebEidCoordinator {
    // MARK: Nested Types

    private enum PreflightBlocker {
      case blockingMessage(String)
      case wrongCard
    }

    private enum PromptApproval {
      case approved(pin: String?)
      case stop(WebEidError)
    }

    // MARK: Functions

    internal func runCeremony(
      for request: WebEidBridgeRequest
    ) async -> Result<WebEidResponsePayload, WebEidError> {
      var retryMessage: String?
      while !activeCancelled, Date() < request.expiresAt {
        let inspected = await WebEidCardRunner.inspectCard(for: request.command)
        guard !activeCancelled else { return .failure(Self.cancelledError) }
        guard Date() < request.expiresAt else { return .failure(Self.timeoutError) }

        switch inspected {
        case .failure(.noCard):
          let prompt = WebEidNativeAlert.ConfirmPrompt(
            title: Self.dialogTitle(for: request.command),
            origin: Self.originText(for: request.command),
            detail: String(localized: "Insert your ID card into the reader."),
            confirmTitle: String(localized: "Try Again"),
            expiresAt: request.expiresAt
          )
          let action = WebEidNativeAlert.requestConfirmation(prompt) { [weak self] in
            self?.activeCancelled ?? true
          }
          if action == .confirmed { continue }
          return .failure(action == .timedOut ? Self.timeoutError : Self.cancelledError)

        case .failure(let failure):
          return showInspectionFailure(failure, request: request)

        case .success(let preview):
          let step = await runPreviewStep(
            preview: preview,
            request: request,
            retryMessage: &retryMessage
          )
          if let completed = step {
            return completed
          }
        }
      }
      return .failure(activeCancelled ? Self.cancelledError : Self.timeoutError)
    }

    private func runPreviewStep(
      preview: WebEidCardPreview,
      request: WebEidBridgeRequest,
      retryMessage: inout String?
    ) async -> Result<WebEidResponsePayload, WebEidError>? {
      if let blocker = preflightBlocker(preview: preview, command: request.command) {
        return handlePreflightBlocker(blocker, request: request)
      }
      let approval = requestApproval(
        preview: preview,
        request: request,
        retryMessage: retryMessage
      )
      guard case .approved(let enteredPin) = approval else {
        if case .stop(let error) = approval {
          return .failure(error)
        }
        return .failure(Self.cancelledError)
      }

      retryMessage = nil
      let execution = await execute(
        command: request.command,
        preview: preview,
        pin: enteredPin
      )
      guard !activeCancelled else { return .failure(Self.cancelledError) }
      guard Date() < request.expiresAt else { return .failure(Self.timeoutError) }
      return handleExecution(execution, request: request, retryMessage: &retryMessage)
    }

    private func requestApproval(
      preview: WebEidCardPreview,
      request: WebEidBridgeRequest,
      retryMessage: String?
    ) -> PromptApproval {
      if let role = Self.requiredRole(for: request.command) {
        let prompt = WebEidNativeAlert.PinPrompt(
          role: role,
          origin: Self.originText(for: request.command),
          holderName: preview.holderName,
          retryMessage: retryMessage,
          confirmTitle: Self.confirmTitle(for: request.command),
          limits: PinEntryLimits(preview.pinLengths, role: role),
          expiresAt: request.expiresAt
        )
        let outcome = WebEidNativeAlert.requestPin(prompt) { [weak self] in
          self?.activeCancelled ?? true
        }
        switch outcome {
        case .entered(let digits):
          return .approved(pin: digits)

        case .timedOut:
          return .stop(Self.timeoutError)

        case .cancelled:
          return .stop(Self.cancelledError)
        }
      }

      let prompt = WebEidNativeAlert.ConfirmPrompt(
        title: Self.dialogTitle(for: request.command),
        origin: Self.originText(for: request.command),
        detail: preview.holderName,
        confirmTitle: Self.confirmTitle(for: request.command),
        expiresAt: request.expiresAt
      )
      let outcome = WebEidNativeAlert.requestConfirmation(prompt) { [weak self] in
        self?.activeCancelled ?? true
      }
      switch outcome {
      case .confirmed:
        return .approved(pin: nil)

      case .timedOut:
        return .stop(Self.timeoutError)

      case .cancelled:
        return .stop(Self.cancelledError)
      }
    }

    private func preflightBlocker(
      preview: WebEidCardPreview,
      command: WebEidCommand
    ) -> PreflightBlocker? {
      if !preview.certificateMatchesExpected {
        return .wrongCard
      }
      if preview.pin2RequiresChangeBeforeSigning, Self.requiredRole(for: command) == .pin2 {
        return .blockingMessage(String(localized: "Change PIN 2 to sign documents."))
      }
      guard let role = Self.requiredRole(for: command) else { return nil }
      if case .locked = preview.retryProbe {
        return .blockingMessage(CredentialOutcomeMessage.blocked(role))
      }
      if preview.retryFloorVerdict != .proceed {
        let remaining: RetryCount? =
          if case .remaining(let count) = preview.retryProbe { count } else { nil }
        return .blockingMessage(
          CredentialOutcomeMessage.floorRefusal(
            role: role,
            verdict: preview.retryFloorVerdict,
            remaining: remaining
          )
        )
      }
      return nil
    }

    private func handlePreflightBlocker(
      _ blocker: PreflightBlocker,
      request: WebEidBridgeRequest
    ) -> Result<WebEidResponsePayload, WebEidError>? {
      switch blocker {
      case .wrongCard:
        let prompt = WebEidNativeAlert.ConfirmPrompt(
          title: Self.dialogTitle(for: request.command),
          origin: Self.originText(for: request.command),
          detail: String(localized: "Insert the card selected for signing."),
          confirmTitle: String(localized: "Try Again"),
          expiresAt: request.expiresAt
        )
        let action = WebEidNativeAlert.requestConfirmation(prompt) { [weak self] in
          self?.activeCancelled ?? true
        }
        if action == .confirmed { return nil }
        return .failure(action == .timedOut ? Self.timeoutError : Self.cancelledError)

      case .blockingMessage(let message):
        showBlocking(message, request: request)
        return .failure(Date() >= request.expiresAt ? Self.timeoutError : Self.cancelledError)
      }
    }

    private func execute(
      command: WebEidCommand,
      preview: WebEidCardPreview,
      pin: String?
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
          pin1: pin ?? "",
          expectedIdentity: identity
        )

      case .getSigningCertificate:
        return await WebEidCardRunner.executeGetSigningCertificate(
          expectedIdentity: identity
        )

      case .sign(let signRequest):
        return await WebEidCardRunner.executeSign(
          request: signRequest,
          pin2: pin ?? "",
          expectedChipSerial: preview.chipSerial
        )

      case .status:
        return .failure(.cardError)
      }
    }

    private func handleExecution(
      _ execution: Result<WebEidResponsePayload, WebEidCardFailure>,
      request: WebEidBridgeRequest,
      retryMessage: inout String?
    ) -> Result<WebEidResponsePayload, WebEidError>? {
      switch execution {
      case .success(let payload):
        return .success(payload)

      case .failure(let failure):
        return handleExecutionFailure(failure, request: request, retryMessage: &retryMessage)
      }
    }

    private func handleExecutionFailure(
      _ failure: WebEidCardFailure,
      request: WebEidBridgeRequest,
      retryMessage: inout String?
    ) -> Result<WebEidResponsePayload, WebEidError>? {
      let role = Self.requiredRole(for: request.command) ?? .pin1
      switch failure {
      case .pinRejected(let remaining):
        return handlePinRejected(
          role: role,
          remaining: remaining,
          request: request,
          retryMessage: &retryMessage
        )

      case .pinBlocked:
        showBlocking(CredentialOutcomeMessage.blocked(role), request: request)
        return .failure(Self.cancelledError)

      case .retryFloorRefused(let verdict, let remaining):
        let message = CredentialOutcomeMessage.floorRefusal(
          role: role,
          verdict: verdict,
          remaining: remaining
        )
        showBlocking(message, request: request)
        return .failure(Self.cancelledError)

      case .pin2RequiresChangeBeforeSigning:
        showBlocking(String(localized: "Change PIN 2 to sign documents."), request: request)
        return .failure(Self.cancelledError)

      case .invalidated:
        showBlocking(
          String(localized: "The credential on the card is invalidated."),
          request: request
        )
        return .failure(Self.cancelledError)

      case .certificateMismatch, .noCard:
        return nil

      case .invalidPinEntry:
        retryMessage = String(localized: "Check the PIN length and try again.")
        return nil

      case .unsupportedAlgorithm, .certificateUnavailable, .cardError:
        return .failure(WebEidError(code: .nativeFatal, message: "Card operation failed"))
      }
    }

    private func handlePinRejected(
      role: CredentialRole,
      remaining: RetryCount,
      request: WebEidBridgeRequest,
      retryMessage: inout String?
    ) -> Result<WebEidResponsePayload, WebEidError>? {
      let presented: PresentedCredential = role == .pin2 ? .pin2 : .pin1
      if RetryFloor.evaluate(freshReading: remaining) == .proceed {
        retryMessage = CredentialOutcomeMessage.rejection(presented, remaining: remaining)
        return nil
      }
      let message = CredentialOutcomeMessage.floorRefusal(
        role: role,
        verdict: .refuseLowAttempts,
        remaining: remaining
      )
      showBlocking(message, request: request)
      return .failure(Self.cancelledError)
    }

    private func showInspectionFailure(
      _ failure: WebEidCardFailure,
      request: WebEidBridgeRequest
    ) -> Result<WebEidResponsePayload, WebEidError> {
      let message =
        failure == .certificateUnavailable
        ? String(localized: "No suitable certificate was found on the card.")
        : String(localized: "Could not read the card.")
      showBlocking(message, request: request)
      return .failure(WebEidError(code: .nativeFatal, message: "Card inspection failed"))
    }

    private func showBlocking(_ message: String, request: WebEidBridgeRequest) {
      WebEidNativeAlert.showBlockingNotice(
        title: Self.dialogTitle(for: request.command),
        origin: Self.originText(for: request.command),
        message: message,
        expiresAt: request.expiresAt,
        isCancelled: { [weak self] in self?.activeCancelled ?? true }
      )
    }
  }

#endif
