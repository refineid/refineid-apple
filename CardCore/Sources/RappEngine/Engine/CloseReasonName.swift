// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The registered `session.close` reasons the engine itself sends, named
/// once (RAPP v26.10.22 §7.1).
internal enum CloseReasonName {
  internal static let pairingRevoked = "pairing_revoked"
  internal static let protocolViolation = "protocol_violation"
}
