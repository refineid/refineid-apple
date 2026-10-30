// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the prime store holds for one card, said without saying any of it.
///
/// A primed record carries the card access number, the authentication
/// certificate, its issuer and the chip serial. A diagnostics screen
/// needs to know whether each of those arrived, and nothing more: a
/// missing issuer and a missing certificate are different faults, and
/// telling them apart is the entire value. So this reports presence and
/// sizes -- never a byte of content, and never the serial itself.
///
/// The instance identifier is carried because it is what correlates a
/// prime with the token identifier CryptoTokenKit publishes. It is a
/// digest of the card's answer to reset or of its certificate, not a
/// serial and not a name.
public struct PrimePresence: Equatable, Sendable {
  /// The name this card is primed under.
  public let instance: String

  /// Whether the record carries a card access number PACE can run with.
  public let hasCardAccessNumber: Bool

  /// Size of the stored authentication certificate, in bytes.
  public let certificateBytes: Int

  /// Size of the stored issuing-CA certificate, or zero when the card
  /// offered none.
  public let issuerBytes: Int

  /// Whether the record carries the chip serial the prime read.
  public let hasChipSerial: Bool
}
