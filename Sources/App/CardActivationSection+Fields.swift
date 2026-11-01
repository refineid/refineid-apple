// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension CardActivationSection {
  /// One new PIN and its repeat, judged against the lengths the card
  /// accepts for the PIN.
  internal struct NewPinEntries {
    internal let new: String
    internal let repeated: String
    internal let limits: PinEntryLimits

    /// The new PIN has an accepted length.
    internal var isValid: Bool {
      limits.accepts(new)
    }

    /// The repeat matches a valid new PIN.
    internal var repeatedIsValid: Bool {
      isValid && repeated == new
    }

    /// Both entries have an accepted length but differ.
    internal var differ: Bool {
      isValid && limits.accepts(repeated) && repeated != new
    }
  }

  /// The keyboard path through the section.
  internal enum Field {
    case entry
    case pin1
    case pin1Repeat
    case pin2
    case pin2Repeat
  }

  /// Whether the form asks for PIN 1 because the card still waits for it.
  internal var asksPin1: Bool {
    model.activationNeeds.pin1
  }

  /// Whether the form asks for PIN 2 because the card still waits for it.
  internal var asksPin2: Bool {
    model.activationNeeds.pin2
  }

  /// Whether the card waits for neither PIN, so the code is the only
  /// group on screen.
  internal var asksNoPin: Bool {
    !asksPin1 && !asksPin2
  }

  /// The fields on screen, in the order Return walks them.
  internal var shownFields: [Field] {
    [.entry]
      + (asksPin1 ? [.pin1, .pin1Repeat] : [])
      + (asksPin2 ? [.pin2, .pin2Repeat] : [])
  }
}
