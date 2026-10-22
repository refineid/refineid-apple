// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.21 §2.2.1 and §4.3).

internal struct SelectionVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case announcedHex = "announced_hex"
    case candidates = "candidates"
    case limit = "limit"
    case name = "name"
  }

  internal let name: String
  internal let limit: Int
  internal let candidates: [SelectionCandidate]
  internal let announcedHex: [String]
}
