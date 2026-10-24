// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// An operation that holds the card against the phone's own antenna, and
/// so draws a meter on the NFC sheet.
internal enum NearFieldOperation: Sendable, Equatable, CaseIterable {
  /// Activation of a card still in its factory state.
  case activation

  /// A browser authentication for a paired computer.
  case authentication

  /// A read of the card's retry counters and activation state.
  case cardStatus

  /// PIN 1 changed with PIN 1.
  case changePin1

  /// PIN 2 changed with PIN 2.
  case changePin2

  /// A certificate read for a paired computer.
  case identity

  /// PIN 1 reset with the PUK.
  case resetPin1

  /// PIN 2 reset with the PUK.
  case resetPin2

  /// The first setup that teaches this iPhone the card.
  case setup

  /// A qualified signature with PIN 2, local or for a paired computer.
  case signature

  /// The steps, in the order they happen.
  internal var steps: [NearFieldStep] {
    switch self {
    case .setup:
      [.found, .secureChannel, .certificate, .stored, .registered]

    case .authentication, .signature:
      [.found, .secureChannel, .certificate, .credential, .signature]

    case .cardStatus, .identity:
      [.found, .secureChannel, .certificate]

    case .activation, .changePin1, .changePin2, .resetPin1, .resetPin2:
      [.found, .secureChannel, .credential]
    }
  }

  /// The operation's name in progressive form, the meter's first line.
  internal var title: String {
    switch self {
    case .activation:
      String(localized: "Activating Card")

    case .authentication:
      String(localized: "Authenticating")

    case .cardStatus, .identity, .setup:
      String(localized: "Reading Identity Card")

    case .changePin1:
      String(localized: "Changing PIN 1")

    case .changePin2:
      String(localized: "Changing PIN 2")

    case .resetPin1:
      String(localized: "Resetting PIN 1")

    case .resetPin2:
      String(localized: "Resetting PIN 2")

    case .signature:
      String(localized: "Signing")
    }
  }
}
