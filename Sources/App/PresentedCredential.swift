// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The credential the holder typed for an operation: one of the card's
/// PINs or PUK, or the activation entry that stands in for one.
internal enum PresentedCredential: Equatable, Sendable {
  case activationCode
  case activationPin
  case pin1
  case pin2
  case puk

  /// The refusal when the counter guarding this credential could not
  /// be read, named in full as `Documentation/design/ui.md` sets out.
  internal var unreadableCounterMessage: String {
    switch self {
    case .pin1:
      String(localized: "The Basic PIN 1 retry counter could not be read; nothing was sent.")

    case .pin2:
      String(localized: "The Signature PIN 2 retry counter could not be read; nothing was sent.")

    case .puk:
      String(localized: "The PUK retry counter could not be read; nothing was sent.")

    case .activationCode, .activationPin:
      String(localized: "The activation PIN retry counter could not be read; nothing was sent.")
    }
  }

  internal init(_ role: CredentialRole) {
    switch role {
    case .pin1:
      self = .pin1

    case .pin2:
      self = .pin2

    case .puk:
      self = .puk
    }
  }

  /// The entry an activation of `scheme` asks for.
  internal init(activation scheme: ActivationScheme) {
    switch scheme {
    case .activationCodeIsPuk:
      self = .activationCode

    case .presetActivationPin:
      self = .activationPin
    }
  }
}
