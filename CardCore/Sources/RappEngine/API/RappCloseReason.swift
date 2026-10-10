// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// `close-reason-val` (RAPP v26.10.10 §7.1).
public enum RappCloseReason: String, CaseIterable, Equatable, Sendable {
  case cardUnavailable = "card_unavailable"
  case complete = "complete"
  case credentialRejected = "credential_rejected"
  case normal = "normal"
  case pairingRevoked = "pairing_revoked"
  case policy = "policy"
  case protocolViolation = "protocol_violation"
  /// The custodian stopped serving because its holder switched remote
  /// access off or quit; a requester drops the card at once.
  case serviceWithdrawn = "service_withdrawn"
  case shutdown = "shutdown"
  case userDisconnect = "user_disconnect"
}
