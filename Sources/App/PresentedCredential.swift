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

  /// The name used inside a sentence.
  internal var name: String {
    switch self {
    case .pin1:
      String(localized: "PIN 1")

    case .pin2:
      String(localized: "PIN 2")

    case .puk:
      String(localized: "PUK")

    case .activationCode:
      String(localized: "activation code")

    case .activationPin:
      String(localized: "activation PIN")
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
