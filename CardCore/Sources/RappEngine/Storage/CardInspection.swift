// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Counter-safe view of the card's authentication state.
///
/// The `inspect_card` answer (RAPP v26.10.1 §9.1) carries the card's answer
/// to reset; the factory flags and counters travel beside it as this
/// implementation's own response fields.
internal struct CardInspection: Equatable {
  /// The answer to reset, or its historical bytes where the platform hides
  /// the rest; empty when the platform exposes neither.
  internal var answerToReset = Data()
  internal var pin1Factory: Bool
  internal var pin2Factory: Bool
  internal var pin1Attempts: UInt8?
  internal var pin2Attempts: UInt8?
  internal var pukAttempts: UInt8?

  internal init(
    pin1Factory: Bool,
    pin2Factory: Bool,
    pin1Attempts: UInt8?,
    pin2Attempts: UInt8?,
    pukAttempts: UInt8?
  ) {
    self.pin1Factory = pin1Factory
    self.pin2Factory = pin2Factory
    self.pin1Attempts = pin1Attempts
    self.pin2Attempts = pin2Attempts
    self.pukAttempts = pukAttempts
  }
  /// An inspection that reported no attempt counters.
  internal init(pin1Factory: Bool, pin2Factory: Bool) {
    self.init(
      pin1Factory: pin1Factory, pin2Factory: pin2Factory, pin1Attempts: nil,
      pin2Attempts: nil, pukAttempts: nil)
  }
}
