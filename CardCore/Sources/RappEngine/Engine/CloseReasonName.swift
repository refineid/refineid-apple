// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The registered session.close reason vocabulary, named once.
internal enum CloseReasonName {
  internal static let pairingRevoked = "pairing_revoked"
  internal static let protocolViolation = "protocol_violation"
  /// A custodian that can no longer serve the card (RAPP v26.10.9 §7.1).
  internal static let cardUnavailable = "card_unavailable"

  /// Whether this close reason carries the Section 14.6 pairing notice.
  internal static func revokesPairing(_ reason: String) -> Bool {
    reason == pairingRevoked || reason == protocolViolation
  }
}
