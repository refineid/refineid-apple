// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One rotating hint: a rendezvous token, a window number, and its hint.
internal struct DiscoveryHintCorpusVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case epoch = "epoch"
    case hintHex = "hint_hex"
    case name = "name"
    case rendezvousTokenHex = "rendezvous_token_hex"
  }

  internal let name: String
  internal let rendezvousTokenHex: String
  internal let epoch: UInt64
  internal let hintHex: String
}
