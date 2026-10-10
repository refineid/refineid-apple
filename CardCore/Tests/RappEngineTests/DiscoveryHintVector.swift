// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.10 §2.2.1 and §4.3).

internal struct DiscoveryHintVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case discoveryHintHex = "discovery_hint_hex"
    case epoch = "epoch"
    case name = "name"
    case unixTimeSeconds = "unix_time_seconds"
  }

  internal let name: String
  internal let unixTimeSeconds: UInt64
  internal let epoch: UInt64
  internal let discoveryHintHex: String
}
