// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import AppKit
  import CardCore
  import Foundation

  /// The native PIN prompt the localhost SCS presents.
  ///
  /// Displays the sanitized `Origin`, action, holder name, and SHA-256
  /// digest without stealing focus from other apps, clears the secure
  /// text field immediately on dismissal, and aborts if the calling
  /// connection disconnects or the SCS stops.
  internal enum ScsPinPrompt {
    /// Display fields describing one consent and PIN ceremony.
    internal struct Context: Sendable {
      internal let role: CredentialRole
      internal let origin: String?
      internal let purpose: ScsSignPurpose
      internal let signerName: String?
      internal let sha256Hex: String
    }

    private final class Box<Value: ~Copyable>: @unchecked Sendable {
      var value: Value

      init(_ value: consuming Value) {
        self.value = value
      }
    }

    private static let fieldWidth: CGFloat = 220
    private static let fieldHeight: CGFloat = 24
    @MainActor private static var modalActive = false

    /// Requests the credential for `context`, tied to `cancellation`.
    internal static func request(
      context: Context,
      cancellation: ScsPromptCancellationToken
    ) -> ScsEnteredPin {
      guard !cancellation.isCancelled else { return .cancelled }
      let box = Box<ScsEnteredPin>(.cancelled)
      DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          box.value = Self.presentPrompt(context: context, cancellation: cancellation)
        }
      }
      var taken: ScsEnteredPin = .cancelled
      swap(&taken, &box.value)
      return taken
    }

    /// Builds the localized prompt with its consent details and SHA-256
    /// fingerprint.
    @MainActor
    internal static func makeAlert(
      context: Context,
      bundle: Bundle
    ) -> NSAlert {
      let alert = NSAlert()
      alert.messageText = CredentialLabels.entryPrompt(for: context.role, bundle: bundle)
      alert.informativeText = ScsConsentDetails.format(
        origin: context.origin,
        purpose: context.purpose,
        signerName: context.signerName,
        sha256Hex: context.sha256Hex,
        bundle: bundle
      )
      let field = NSSecureTextField(
        frame: NSRect(x: 0, y: 0, width: Self.fieldWidth, height: Self.fieldHeight))
      alert.accessoryView = field
      alert.addButton(
        withTitle: ScsConsentDetails.confirmTitle(purpose: context.purpose, bundle: bundle))
      alert.addButton(withTitle: String(localized: "Cancel", bundle: bundle))
      alert.window.initialFirstResponder = field
      return alert
    }

    @MainActor
    private static func presentPrompt(
      context: Context,
      cancellation: ScsPromptCancellationToken
    ) -> ScsEnteredPin {
      guard !modalActive else { return .busy }
      guard !cancellation.isCancelled else { return .cancelled }
      modalActive = true
      ScsService.shared.setPendingRequest(origin: context.origin)
      defer {
        modalActive = false
        ScsService.shared.clearPendingRequest()
      }
      let alert = makeAlert(context: context, bundle: .main)
      guard let field = alert.accessoryView as? NSSecureTextField else {
        return .cancelled
      }
      defer { field.stringValue = "" }
      guard
        cancellation.installAbort({
          CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated {
              NSApp.abortModal()
            }
          }
          CFRunLoopWakeUp(CFRunLoopGetMain())
        })
      else {
        return .cancelled
      }
      defer { cancellation.clearAbort() }
      _ = NSApp.requestUserAttention(.informationalRequest)
      let modalResponse = alert.runModal()
      let rawDigits = field.stringValue
      field.stringValue = ""
      guard modalResponse == .alertFirstButtonReturn, !cancellation.isCancelled else {
        return .cancelled
      }
      return parseEnteredDigits(rawDigits, role: context.role)
    }

    private static func parseEnteredDigits(
      _ digits: String,
      role: CredentialRole
    ) -> ScsEnteredPin {
      switch role {
      case .pin1:
        guard let pin = Pin1(digits: digits) else { return .invalidFormat }
        return .pin1(pin)

      case .pin2:
        guard let pin = Pin2(digits: digits) else { return .invalidFormat }
        return .pin2(pin)

      default:
        return .invalidFormat
      }
    }
  }
#endif
