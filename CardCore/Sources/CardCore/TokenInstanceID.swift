// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The CryptoTokenKit token instance ID (`TKTokenInstanceID`) for one physical card.
///
/// It is the name `ctkd` knows the token by, not an identity, and keys no
/// secret; PIN memory binds to ``ChipSerial``.
///
/// One card has one token across transports and authentication-key
/// generations. The identifier contains the serial printed on the card, so a
/// diagnostics report can be checked against the plastic without translating
/// an ATR hash or certificate fingerprint.
public struct TokenInstanceID: Equatable, Hashable, Sendable {
  /// Namespace owned by the RefineID token driver.
  private static let prefix = "refineid-card-"

  /// The public CryptoTokenKit instance ID.
  public let value: String

  /// Builds the instance ID from a supported FINEID chip serial.
  public init?(chipSerial: ChipSerial) {
    guard let printed = PrintedSerial(chipSerial: chipSerial) else {
      return nil
    }
    self.value = Self.prefix + printed.value.lowercased()
  }
}
