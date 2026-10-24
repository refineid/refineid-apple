// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Whether PIN 1 may be held for silent reuse, decided from the probe that
/// precedes every PIN-bearing command.
///
/// A value is held only on a card whose PIN 1 counter is at its full
/// allowance: a probe that reads five attempts left, or one the card
/// answers as verified, which proves the last VERIFY succeeded and set the
/// counter to its limit (FINEID S1 v4.2 section 3.5). Any other answer
/// means someone has been wrong on this card, or nothing is known, and a
/// held value is dropped before the card is commanded. The retry floor
/// decides whether an attempt may be sent at all; this decides only whether
/// its PIN may be kept afterwards.
public enum Pin1Retention {
  /// True when the probe permits holding PIN 1 for this card.
  public static func permitsHolding(after probe: RetryProbeOutcome) -> Bool {
    switch probe {
    case .remaining(let count):
      count.isPristine

    case .verified:
      true

    case .invalidated, .locked, .noInformation, .other:
      false
    }
  }
}
