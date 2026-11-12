// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  extension DocumentSigningView {
    /// Signs with the demonstration card, which authorizes in memory.
    ///
    /// Lives apart from the view so neither outgrows the body-length gate.
    internal func signWithVirtualCard(pin2: String) async {
      let result = await DemoMode.shared.authorizeQualifiedSignature(pin2: pin2)
      switch result {
      case .success:
        finishSuccessfully()

      case .invalidEntry:
        showFailure(
          text("error.pin2Format", "Signature PIN 2 must contain 6 to 12 digits."))

      case .blocked:
        showFailure(
          text(
            "error.pin2Blocked",
            "Signature PIN 2 is blocked. Reset it in PIN settings."))

      case .rejected(let remaining):
        showFailure(
          text("error.pin2Incorrect", "Signature PIN 2 is incorrect.")
            + "\n"
            + String(
              format: text(
                "error.attempts",
                "You have %d attempts remaining."),
              Int(remaining)))

      case .refusedLowAttempts(let remaining):
        showFailure(
          text("error.operationRefused", "Operation refused.")
            + "\n"
            + String(
              format: text(
                "error.attempts",
                "You have %d attempts remaining."),
              Int(remaining)))

      case .certificateUnavailable:
        showFailure(
          text(
            "error.signatureCertificate",
            "The signature certificate is unavailable."))

      case .transportFailure:
        showFailure(
          text("error.connection", "The card connection was lost."))
      }
    }
  }
#endif
