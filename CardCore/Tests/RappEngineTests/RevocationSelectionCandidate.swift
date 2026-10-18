// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One revoked pairing's hint and revocation time.
internal struct RevocationSelectionCandidate: Decodable {
  private enum CodingKeys: String, CodingKey {
    case hintHex = "hint_hex"
    case revokedAtMs = "revoked_at_ms"
  }

  internal let hintHex: String
  internal let revokedAtMs: UInt64
}
