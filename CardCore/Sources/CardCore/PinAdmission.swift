// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Whether the card's counter lets a signature send its PIN, decided from
/// the probe that precedes the PIN-bearing command.
///
/// The retry floor (``RetryFloor``) serves a PIN only at five, four or
/// three attempts left, or on a verified card. A held PIN 1 is narrower:
/// it is sent only while the counter shows no refusal since the card
/// accepted it, which is the full allowance or a verified answer
/// (``Pin1Retention``). Any other counter means someone has been wrong on
/// this card, so the held value is not sent and the holder is asked
/// instead (RAPP v26.10.29 §11 item 2).
public enum PinAdmission: Equatable, Sendable {
  /// The credential is blocked.
  case credentialBlocked

  /// The credential's reference data is invalidated.
  case credentialInvalidated

  /// The counter shows a refusal since the held PIN 1 was accepted.
  case heldPin1Unconfirmed

  /// The PIN may be sent.
  case proceed

  /// The retry floor refuses the counter.
  case retryFloor(RetryFloorVerdict)

  /// Where the PIN about to be sent comes from.
  public enum Spending: Equatable, Sendable {
    /// Typed by the holder for this operation.
    case entered
    /// PIN 1 held from an earlier operation the card accepted.
    case heldPin1
  }

  /// Decides from one fresh probe of the credential the PIN is checked as.
  public init(probe: RetryProbeOutcome, spending: Spending) {
    switch probe {
    case .locked:
      self = .credentialBlocked

    case .invalidated:
      self = .credentialInvalidated

    case .remaining, .verified:
      let verdict = RetryFloor.evaluate(probeOutcome: probe)
      if verdict != .proceed {
        self = .retryFloor(verdict)
      } else if spending == .heldPin1, !Pin1Retention.permitsHolding(after: probe) {
        self = .heldPin1Unconfirmed
      } else {
        self = .proceed
      }

    case .noInformation, .other:
      self = .retryFloor(.refuseUnreadable)
    }
  }
}
