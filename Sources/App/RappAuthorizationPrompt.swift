// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The words of the phone's PIN prompt for a paired computer's request: a
/// title naming the act, and one sentence naming the computer and, for a
/// signature, the documents.
///
/// The computer's display name and the document names are shown as given;
/// they were refined where they entered.
internal enum RappAuthorizationPrompt {
  internal static let authenticationTitle = String(localized: "Authentication")

  internal static let signatureTitle = String(localized: "Signature")

  internal static func authenticationMessage(computer: String) -> String {
    String(localized: "\(computer) asks you to authenticate.")
  }

  /// One document by its name, a batch as a list in signing order, and a
  /// request that names none without a document.
  internal static func signatureMessage(computer: String, documents: [String]) -> String {
    switch documents.count {
    case 0:
      return String(localized: "\(computer) asks you to sign.")

    case 1:
      return String(localized: "\(computer) asks you to sign \(documents[0]).")

    default:
      let named = ListFormatter.localizedString(byJoining: documents)
      return String(localized: "\(computer) asks you to sign the documents \(named).")
    }
  }
}
