// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Combine
  import Foundation
  import Observation

  /// Presentation model driving one interactive macOS Web eID consent and PIN
  /// window on behalf of Safari.
  @MainActor
  @Observable
  internal final class WebEidPromptModel {
    // MARK: Nested Types

    internal enum CardState: Equatable {
      case loading
      case waitingForCard
      case ready(WebEidCardPreview)
      case unavailable(String)
    }

    // MARK: Properties

    internal let command: WebEidCommand
    internal var pinDigits = ""
    internal var cardState: CardState = .loading
    internal var isSubmitting = false
    internal var errorMessage: String?
    internal var isOperationBlocked = false

    @ObservationIgnored private var completion:
      ((Result<WebEidResponsePayload, WebEidError>) -> Void)?
    @ObservationIgnored private var presenceCancellables: Set<AnyCancellable> = []
    @ObservationIgnored internal var activeTask: Task<Void, Never>?

    // MARK: Computed Properties

    internal var originText: String {
      switch command {
      case .authenticate(let origin, _, _),
        .getSigningCertificate(let origin, _):
        origin.value

      case .sign(let request):
        request.origin.value

      case .status:
        ""
      }
    }

    internal var requiredRole: CredentialRole? {
      switch command {
      case .authenticate:
        .pin1

      case .sign:
        .pin2

      case .status, .getSigningCertificate:
        nil
      }
    }

    internal var windowTitle: String {
      switch command {
      case .authenticate:
        String(localized: "Website Login")

      case .getSigningCertificate:
        String(localized: "Share Signing Certificate")

      case .sign:
        String(localized: "Sign Document")

      case .status:
        String(localized: "RefineID")
      }
    }

    internal var confirmButtonTitle: String {
      switch command {
      case .authenticate:
        String(localized: "Log in")

      case .getSigningCertificate:
        String(localized: "Confirm")

      case .sign:
        String(localized: "Sign")

      case .status:
        String(localized: "Confirm")
      }
    }

    internal var pinLimits: PinEntryLimits? {
      guard
        case .ready(let preview) = cardState,
        let role = requiredRole
      else {
        return nil
      }
      return PinEntryLimits(preview.pinLengths, role: role)
    }

    internal var canSubmit: Bool {
      guard !isSubmitting, !isOperationBlocked, case .ready = cardState else {
        return false
      }
      guard let limits = pinLimits else {
        return requiredRole == nil
      }
      return limits.accepts(pinDigits)
    }

    // MARK: Lifecycle

    internal init(
      command: WebEidCommand,
      completion: @escaping (Result<WebEidResponsePayload, WebEidError>) -> Void
    ) {
      self.command = command
      self.completion = completion
      observeCardPresence()
      reloadCard()
    }

    // MARK: Functions

    internal func limitPinEntry(_ raw: String) {
      guard let limits = pinLimits else {
        pinDigits = LimitedDigits.digits(raw, maximumCount: Pin1.maximumDigitCount)
        return
      }
      pinDigits = limits.limited(raw)
    }

    internal func cancel() {
      finish(
        .failure(
          WebEidError(code: .userCancelled, message: "User cancelled the Web eID request")
        )
      )
    }

    internal func expireTimeout() {
      finish(
        .failure(
          WebEidError(code: .userTimeout, message: "Web eID user interaction timed out")
        )
      )
    }

    internal func reloadCard() {
      activeTask?.cancel()
      errorMessage = nil
      isOperationBlocked = false
      guard CardPresence.shared.isReaderCardPresent else {
        cardState = .waitingForCard
        return
      }
      cardState = .loading
      activeTask = Task { [weak self] in
        guard let self else { return }
        let inspected = await WebEidCardRunner.inspectCard(for: command)
        guard !Task.isCancelled else { return }
        applyInspection(inspected)
      }
    }

    internal func finish(_ result: Result<WebEidResponsePayload, WebEidError>) {
      activeTask?.cancel()
      activeTask = nil
      presenceCancellables.removeAll()
      pinDigits = ""
      guard let handler = completion else { return }
      completion = nil
      handler(result)
    }

    private func observeCardPresence() {
      let presence = CardPresence.shared
      presence.$isReaderCardReady
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] ready in
          guard let self, !isSubmitting else { return }
          if ready {
            reloadCard()
          }
        }
        .store(in: &presenceCancellables)

      presence.$isReaderCardPresent
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] present in
          guard let self, !isSubmitting else { return }
          if !present {
            pinDigits = ""
            errorMessage = nil
            isOperationBlocked = false
            cardState = .waitingForCard
          }
        }
        .store(in: &presenceCancellables)
    }
  }

#endif
