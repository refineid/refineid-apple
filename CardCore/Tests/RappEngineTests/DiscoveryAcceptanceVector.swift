// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.18 §2.2.1 and §4.3).

internal struct DiscoveryAcceptanceVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case expected = "expected"
    case name = "name"
    case publishedHintHex = "published_hint_hex"
    case requesterEpoch = "requester_epoch"
  }

  internal let name: String
  internal let publishedHintHex: String
  internal let requesterEpoch: UInt64
  internal let expected: String
}
