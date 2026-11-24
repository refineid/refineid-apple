// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The two distinct identifiers read from one physical card session.
///
/// ``chipSerial`` is the full card-bound security identity used for PIN 1
/// memory, rejected-PIN latches, and card-swap checks. ``printedSerial`` is
/// the human-auditable identifier printed on the plastic card, used only to
/// build the public CryptoTokenKit ``TokenInstanceID``.
public struct CardIdentitySerials: Equatable, Sendable {
  /// The card's full chip-level security serial.
  public let chipSerial: ChipSerial

  /// The card's printed serial or document number.
  public let printedSerial: PrintedSerial

  /// Pairs the chip serial and printed serial read in one session.
  public init(chipSerial: ChipSerial, printedSerial: PrintedSerial) {
    self.chipSerial = chipSerial
    self.printedSerial = printedSerial
  }
}
