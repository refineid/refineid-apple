// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  extension SignDocumentModel {
    /// Authorizes a simulated signature with the virtual ID card.
    ///
    /// The simulated signature carries no timestamp, so it is named by
    /// the clock.
    internal func signWithVirtualCard(
      pin2: String,
      from source: URL,
      appearance: Int
    ) async -> SignedDocument? {
      let result = await DemoMode.shared.authorizeQualifiedSignature(pin2: pin2)
      guard appearance == cardAppearance else { return nil }
      switch result {
      case .success:
        let sourceData =
          (try? Data(contentsOf: source))
          ?? Data("%PDF-1.4\n% Virtual demonstration document\n%%EOF".utf8)
        return SignedDocument(untimestamped: sourceData, clock: Date())

      case .invalidEntry:
        fail(message: String(localized: "PIN 2 must contain 6 to 12 digits."))
        return nil

      case .blocked:
        fail(
          message: String(
            localized: "PIN 2 is blocked. Reset it in PIN settings."
          )
        )
        return nil

      case .rejected(let remaining):
        fail(
          message: String(localized: "PIN 2 is incorrect.")
            + "\n"
            + String(
              format: String(localized: "You have %d attempts remaining."),
              Int(remaining)
            )
        )
        return nil

      case .refusedLowAttempts(let remaining):
        fail(
          message: String(localized: "Operation refused")
            + "\n"
            + String(
              format: String(localized: "You have %d attempts remaining."),
              Int(remaining)
            )
        )
        return nil

      case .certificateUnavailable:
        fail(
          message: String(
            localized: "The signature certificate is unavailable."
          )
        )
        return nil

      case .transportFailure:
        fail(message: String(localized: "The card connection was lost."))
        return nil
      }
    }
  }

#endif
