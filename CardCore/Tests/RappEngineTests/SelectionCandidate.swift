// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.29 §2.2.1 and §4.3).

/// One pairing a selection vector ranks.
internal struct SelectionCandidate: Decodable {
  private enum CodingKeys: String, CodingKey {
    case hintHex = "hint_hex"
    case lastUsedMs = "last_used_ms"
  }

  internal let hintHex: String
  internal let lastUsedMs: UInt64
}
