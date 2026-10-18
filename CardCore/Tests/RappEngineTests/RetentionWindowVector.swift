// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a retention is announced at an instant.
internal struct RetentionWindowVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case announced = "announced"
    case name = "name"
    case nowMs = "now_ms"
    case revokedAtMs = "revoked_at_ms"
  }

  internal let name: String
  internal let revokedAtMs: UInt64
  internal let nowMs: UInt64
  internal let announced: Bool
}
