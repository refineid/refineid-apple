// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import AppKit
  import CardCore
  import Foundation

  /// The PIN prompt the localhost SCS presents.
  ///
  /// SCS signs arrive from a web page, not from CryptoTokenKit, so
  /// the app itself asks for the credential. The prompt runs on the
  /// main thread and blocks the SCS worker until the holder answers;
  /// cancelling refuses the sign without touching the card.
  internal enum ScsPinPrompt {
    private static let fieldWidth: CGFloat = 220
    private static let fieldHeight: CGFloat = 24

    /// Asks for the named credential; nil when the holder cancels.
    internal static func request(role: CredentialRole) -> String? {
      var answer: String?
      DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          answer = Self.presentPrompt(role: role)
        }
      }
      return answer
    }

    /// Builds the localized prompt without explanatory text.
    @MainActor
    internal static func makeAlert(role: CredentialRole, bundle: Bundle) -> NSAlert {
      let alert = NSAlert()
      alert.messageText = CredentialLabels.entryPrompt(for: role, bundle: bundle)
      let field = NSSecureTextField(
        frame: NSRect(x: 0, y: 0, width: Self.fieldWidth, height: Self.fieldHeight))
      alert.accessoryView = field
      alert.addButton(withTitle: String(localized: "Sign", bundle: bundle))
      alert.addButton(withTitle: String(localized: "Cancel", bundle: bundle))
      alert.window.initialFirstResponder = field
      return alert
    }

    /// Runs the modal prompt; cancellation returns no credential.
    @MainActor
    private static func presentPrompt(role: CredentialRole) -> String? {
      NSApp.activate(ignoringOtherApps: true)
      let alert = makeAlert(role: role, bundle: .main)
      guard alert.runModal() == .alertFirstButtonReturn,
        let field = alert.accessoryView as? NSSecureTextField
      else { return nil }
      return field.stringValue
    }
  }
#endif
