// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The stable CryptoTokenKit instance ID for one physical card.
///
/// One card has one token across transports and authentication-key
/// generations. The identifier contains the serial printed on the card, so a
/// diagnostics report can be checked against the plastic without translating
/// an ATR hash or certificate fingerprint.
public struct CardInstanceIdentifier: Equatable, Hashable, Sendable {
  /// Namespace owned by the RefineID token driver.
  private static let prefix = "refineid-card-"

  /// The public CTK instance identifier.
  public let value: String

  /// Builds the public identifier from a supported FINEID token serial.
  public init?(tokenSerial: TokenSerial) {
    guard let printed = PrintedCardSerial(tokenSerial: tokenSerial) else {
      return nil
    }
    self.value = Self.prefix + printed.value.lowercased()
  }
}
