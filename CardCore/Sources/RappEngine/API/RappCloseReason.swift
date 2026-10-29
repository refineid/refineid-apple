// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// `close-reason-val` (RAPP v26.10.29 §7.1).
public enum RappCloseReason: String, CaseIterable, Equatable, Sendable {
  case cardUnavailable = "card_unavailable"
  case complete = "complete"
  case normal = "normal"
  case pairingRevoked = "pairing_revoked"
  case policy = "policy"
  case protocolViolation = "protocol_violation"
  /// The sender withdrew: a custodian stopped serving, or a requester
  /// stopped using, every pairing (§4.5). The pairing stays.
  case serviceWithdrawn = "service_withdrawn"
  case shutdown = "shutdown"
  case userDisconnect = "user_disconnect"
}
