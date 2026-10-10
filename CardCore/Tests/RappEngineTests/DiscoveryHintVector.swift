// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One `discovery_hint` corpus vector (discovery hierarchy §4.3).
internal struct DiscoveryHintVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case discoveryKeyHex = "discovery_key_hex"
    case epoch = "epoch"
    case hintHex = "hint_hex"
    case name = "name"
    case rendezvousTokenHex = "rendezvous_token_hex"
  }

  internal let name: String
  internal let rendezvousTokenHex: String
  internal let discoveryKeyHex: String
  internal let epoch: UInt64
  internal let hintHex: String
}
