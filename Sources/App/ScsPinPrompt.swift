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
  /// The prompt names the requesting origin and the digest the card
  /// is about to sign. The specification requires the origin
  /// (DVV SCS specification v1.3 §2.1); the digest is what lets the
  /// holder recognise a request for a document they did not choose,
  /// which the origin alone does not distinguish.
  internal enum ScsPinPrompt {
    /// Bytes per group in the printed digest; four bytes is the
    /// conventional fingerprint width and keeps the line wrappable.
    private static let digestGroupByteCount = 4

    /// Hex format for one digest byte.
    private static let hexByteFormat = "%02x"

    /// Separator between printed digest groups.
    private static let digestGroupSeparator = " "

    /// Separator between the origin and digest lines.
    private static let detailLineSeparator = "\n"

    private static let fieldWidth: CGFloat = 220
    private static let fieldHeight: CGFloat = 24

    /// Asks for the named credential; nil when the holder cancels.
    internal static func request(
      role: CredentialRole,
      origin: String?,
      digest: Data,
      hash: SigningHash
    ) -> String? {
      var answer: String?
      DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          answer = Self.presentPrompt(
            role: role, origin: origin, digest: digest, hash: hash)
        }
      }
      return answer
    }

    /// What the holder is told about the request: the Origin header
    /// exactly as it arrived, and the digest that will be signed.
    ///
    /// The digest identifies the bytes the card is handed, which for a
    /// CMS-PAdES sign is the signed-attributes SET rather than the
    /// document. That is deliberate: the prompt has to name what the
    /// key is applied to, and a digest of something else would be a
    /// claim the card does not back.
    ///
    /// The origin is printed verbatim rather than reduced to a host
    /// name, because §2.1 asks for the header's content and the
    /// scheme and port are part of what identifies the requester. A
    /// request that carried no Origin says so in as many words rather
    /// than leaving the line blank: a browser always sends Origin on a
    /// CORS request, so its absence means the requester is not a page,
    /// which the holder needs to see before typing a PIN.
    internal static func consentDetails(
      origin: String?,
      digest: Data,
      hash: SigningHash,
      bundle: Bundle
    ) -> String {
      let originLine =
        origin
        .map { String(localized: "Origin: \($0)", bundle: bundle) }
        ?? String(
          localized: "Origin: (none - the request sent no Origin header)", bundle: bundle)
      let digestLine = String(
        localized: "Digest (\(ScsKeyAlgorithm.scsName(hash: hash))): \(printedDigest(digest))",
        bundle: bundle)
      return originLine + Self.detailLineSeparator + digestLine
    }

    /// Builds the localized prompt with its consent details.
    @MainActor
    internal static func makeAlert(
      role: CredentialRole,
      origin: String?,
      digest: Data,
      hash: SigningHash,
      bundle: Bundle
    ) -> NSAlert {
      let alert = NSAlert()
      alert.messageText = CredentialLabels.entryPrompt(for: role, bundle: bundle)
      alert.informativeText = consentDetails(
        origin: origin, digest: digest, hash: hash, bundle: bundle)
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
      digest: Data,
      hash: SigningHash
    ) -> String? {
      NSApp.activate(ignoringOtherApps: true)
      let alert = makeAlert(
        role: role, origin: origin, digest: digest, hash: hash, bundle: .main)
      guard alert.runModal() == .alertFirstButtonReturn,
        let field = alert.accessoryView as? NSSecureTextField
      else { return nil }
      return field.stringValue
    }

    /// The digest as spaced lowercase hex, grouped for reading.
    private static func printedDigest(_ digest: Data) -> String {
      let bytes = [UInt8](digest)
      return stride(from: 0, to: bytes.count, by: Self.digestGroupByteCount)
        .map { start in
          bytes[start..<min(start + Self.digestGroupByteCount, bytes.count)]
            .map { String(format: Self.hexByteFormat, $0) }
            .joined()
        }
        .joined(separator: Self.digestGroupSeparator)
    }
  }
#endif
