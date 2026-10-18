// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The revocations a custodian announces among a larger set.
internal struct RevocationSelectionVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case announcedHex = "announced_hex"
    case candidates = "candidates"
    case limit = "limit"
    case name = "name"
  }

  internal let name: String
  internal let limit: Int
  internal let candidates: [RevocationSelectionCandidate]
  internal let announcedHex: [String]
}
