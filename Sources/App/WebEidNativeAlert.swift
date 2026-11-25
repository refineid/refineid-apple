// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import Foundation

  /// Native macOS `NSAlert` dialogs for Web eID authentication, certificate
  /// consent, and qualified signing.
  ///
  /// Uses a plain masked `NSSecureTextField` with no reveal toggle so PIN 1
  /// and PIN 2 are never shown in clear text, wipes the field immediately on
  /// dismissal or card removal, and aborts only its own modal window at the
  /// browser request's deadline.
  @MainActor
  internal enum WebEidNativeAlert {
    // MARK: Nested Types

    internal enum Layout {
      internal static let fieldWidth: CGFloat = 240
      internal static let fieldHeight: CGFloat = 24
      internal static let abortRetryIntervalSeconds: TimeInterval = 0.1
    }

    internal enum ConfirmOutcome: Equatable {
      case cancelled
      case confirmed
      case timedOut
    }

    internal enum PinOutcome: Equatable {
      case cancelled
      case cardRemoved
      case entered(String)
      case timedOut
    }

    internal enum ModalOutcome {
      case cardRemoved
      case firstButton
      case other
      case timedOut
    }

    /// Context describing one native PIN prompt.
    internal struct PinPrompt {
      internal let role: CredentialRole
      internal let origin: String
      internal let holderName: String
      internal let retryMessage: String?
      internal let confirmTitle: String
      internal let limits: PinEntryLimits
      internal let expiresAt: Date
    }

    /// Context describing one native confirmation prompt without a PIN field.
    internal struct ConfirmPrompt {
      internal let title: String
      internal let origin: String
      internal let detail: String
      internal let confirmTitle: String
      internal let expiresAt: Date
    }

    /// Options governing one modal alert run.
    internal struct ModalOptions {
      internal let field: NSSecureTextField?
      internal let confirmButton: NSButton?
      internal let observeCardRemoval: Bool
      internal let expiresAt: Date
    }

    /// Keeps the masked `NSSecureTextField` to ASCII digits within the card's
    /// accepted length range and gates the default button until complete.
    private final class PinFieldDelegate: NSObject, NSTextFieldDelegate {
      private let limits: PinEntryLimits
      private weak var confirmButton: NSButton?

      init(limits: PinEntryLimits, confirmButton: NSButton?) {
        self.limits = limits
        self.confirmButton = confirmButton
        super.init()
      }

      func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSecureTextField else { return }
        let filtered = limits.limited(field.stringValue)
        if field.stringValue != filtered {
          field.stringValue = filtered
        }
        confirmButton?.isEnabled = limits.accepts(filtered)
      }
    }

    // MARK: Static Properties

    internal static weak var activeGuard: ModalGuard?

    // MARK: Static Functions

    /// Aborts the currently presented Web eID alert (and no unrelated modal).
    internal static func abortActiveAlert() {
      activeGuard?.clearAndDisableField()
      activeGuard?.requestAbort()
    }

    /// Presents a native macOS `NSAlert` with a masked `NSSecureTextField`
    /// (never revealable) for PIN 1 or PIN 2 entry.
    internal static func requestPin(
      _ prompt: PinPrompt,
      isCancelled: () -> Bool
    ) -> PinOutcome {
      let alert = NSAlert()
      alert.messageText = CredentialLabels.entryPrompt(for: prompt.role, bundle: .main)
      alert.informativeText = formatDetails(
        origin: prompt.origin,
        holderName: prompt.holderName,
        extraMessage: prompt.retryMessage
      )
      let field = makePinField(for: prompt.role)
      alert.accessoryView = field
      let confirmButton = alert.addButton(withTitle: prompt.confirmTitle)
      confirmButton.isEnabled = false
      _ = alert.addButton(withTitle: String(localized: "Cancel"))

      let delegate = PinFieldDelegate(limits: prompt.limits, confirmButton: confirmButton)
      field.delegate = delegate
      alert.layout()
      alert.window.initialFirstResponder = field
      defer {
        field.delegate = nil
        field.stringValue = ""
      }

      let modalResult = withExtendedLifetime(delegate) {
        runWithDeadline(
          alert,
          options: ModalOptions(
            field: field,
            confirmButton: confirmButton,
            observeCardRemoval: true,
            expiresAt: prompt.expiresAt
          ),
          isCancelled: isCancelled
        )
      }
      let digits = field.stringValue
      field.stringValue = ""

      switch modalResult {
      case .firstButton where prompt.limits.accepts(digits):
        return .entered(digits)

      case .cardRemoved:
        return .cardRemoved

      case .timedOut:
        return .timedOut

      case .firstButton, .other:
        return .cancelled
      }
    }

    /// Presents a native macOS confirmation alert without a PIN field (for
    /// `get-signing-certificate` consent or retrying card insertion).
    internal static func requestConfirmation(
      _ prompt: ConfirmPrompt,
      isCancelled: () -> Bool
    ) -> ConfirmOutcome {
      let alert = NSAlert()
      alert.messageText = prompt.title
      alert.informativeText = "\(prompt.origin)\n\n\(prompt.detail)"
      let confirmButton = alert.addButton(withTitle: prompt.confirmTitle)
      _ = alert.addButton(withTitle: String(localized: "Cancel"))

      let outcome = runWithDeadline(
        alert,
        options: ModalOptions(
          field: nil,
          confirmButton: confirmButton,
          observeCardRemoval: false,
          expiresAt: prompt.expiresAt
        ),
        isCancelled: isCancelled
      )
      switch outcome {
      case .firstButton:
        return .confirmed

      case .timedOut:
        return .timedOut

      case .cardRemoved, .other:
        return .cancelled
      }
    }

    /// Presents a native macOS warning alert with a single OK button for
    /// blocking conditions (blocked PIN, retry floor, or initial PIN 2 change).
    internal static func showBlockingNotice(
      title: String,
      origin: String,
      message: String,
      expiresAt: Date,
      isCancelled: () -> Bool
    ) {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = title
      alert.informativeText = "\(origin)\n\n\(message)"
      _ = alert.addButton(withTitle: String(localized: "OK"))
      _ = runWithDeadline(
        alert,
        options: ModalOptions(
          field: nil,
          confirmButton: nil,
          observeCardRemoval: false,
          expiresAt: expiresAt
        ),
        isCancelled: isCancelled
      )
    }

    private static func makePinField(for role: CredentialRole) -> NSSecureTextField {
      let field = NSSecureTextField(
        frame: NSRect(x: 0, y: 0, width: Layout.fieldWidth, height: Layout.fieldHeight)
      )
      field.placeholderString = CredentialLabels.name(for: role)
      field.usesSingleLineMode = true
      return field
    }

    private static func formatDetails(
      origin: String,
      holderName: String,
      extraMessage: String?
    ) -> String {
      var lines = [origin]
      if !holderName.isEmpty {
        lines.append(holderName)
      }
      if let extraMessage, !extraMessage.isEmpty {
        lines.append("")
        lines.append(extraMessage)
      }
      return lines.joined(separator: "\n")
    }
  }

#endif
