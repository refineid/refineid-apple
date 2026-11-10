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
  ///
  /// The prompt names the requesting origin, the kind of request,
  /// and the certificate holder whose key is about to sign: the
  /// context a holder can act on. The signed digest is deliberately
  /// not printed. A holder cannot recover the document from a hash,
  /// services show no hash to compare against, and for CMS signs
  /// the digest covers the signed attributes rather than the
  /// document - so hex would only train the holder to click
  /// through. The specification requires the origin
  /// (DVV SCS specification v1.3 §2.1).
  internal enum ScsPinPrompt {
    private static let fieldWidth: CGFloat = 220
    private static let fieldHeight: CGFloat = 24

    /// Asks for the named credential; nil when the holder cancels.
    internal static func request(
      role: CredentialRole,
      origin: String?,
      purpose: ScsSignPurpose,
      signerName: String?
    ) -> String? {
      var answer: String?
      DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          answer = Self.presentPrompt(
            role: role, origin: origin, purpose: purpose, signerName: signerName)
        }
      }
      return answer
    }

    /// What the holder is told about the request: the Origin header
    /// exactly as it arrived, what the key is asked to do, and whose
    /// certificate holds the key.
    ///
    /// The origin is printed verbatim rather than reduced to a host
    /// name, because §2.1 asks for the header's content and the
    /// scheme and port are part of what identifies the requester. A
    /// request that carried no Origin says so in as many words rather
    /// than leaving the line blank: a browser always sends Origin on a
    /// CORS request, so its absence means the requester is not a page,
    /// which the holder needs to see before typing a PIN. A signer
    /// the card could not name omits its line rather than printing a
    /// placeholder the holder might mistake for a name.
    internal static func consentDetails(
      origin: String?,
      purpose: ScsSignPurpose,
      signerName: String?,
      bundle: Bundle
    ) -> String {
      var lines = [
        originLine(origin: origin, bundle: bundle),
        actionLine(purpose: purpose, bundle: bundle),
      ]
      if let signerName {
        lines.append(
          String(localized: "Signing as: \(signerName)", bundle: bundle))
      }
      return lines.joined(separator: "\n")
    }

    /// The requesting origin, verbatim, or the stated absence.
    private static func originLine(origin: String?, bundle: Bundle) -> String {
      origin
        .map { String(localized: "Origin: \($0)", bundle: bundle) }
        ?? String(
          localized: "Origin: (none - the request sent no Origin header)", bundle: bundle)
    }

    /// What the key is asked to do, in the holder's words: an
    /// authentication request logs in, a qualified request signs.
    private static func actionLine(purpose: ScsSignPurpose, bundle: Bundle) -> String {
      switch purpose {
      case .authentication:
        String(localized: "Action: Log in", bundle: bundle)

      case .qualified:
        String(localized: "Action: Sign document", bundle: bundle)
      }
    }

    /// Builds the localized prompt with its consent details.
    @MainActor
    internal static func makeAlert(
      role: CredentialRole,
      origin: String?,
      purpose: ScsSignPurpose,
      signerName: String?,
      bundle: Bundle
    ) -> NSAlert {
      let alert = NSAlert()
      alert.messageText = CredentialLabels.entryPrompt(for: role, bundle: bundle)
      alert.informativeText = consentDetails(
        origin: origin, purpose: purpose, signerName: signerName, bundle: bundle)
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
    private static func presentPrompt(
      role: CredentialRole,
      origin: String?,
      purpose: ScsSignPurpose,
      signerName: String?
    ) -> String? {
      NSApp.activate(ignoringOtherApps: true)
      let alert = makeAlert(
        role: role, origin: origin, purpose: purpose, signerName: signerName, bundle: .main)
      guard alert.runModal() == .alertFirstButtonReturn,
        let field = alert.accessoryView as? NSSecureTextField
      else { return nil }
      return field.stringValue
    }
  }
#endif
