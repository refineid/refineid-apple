// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One transcript hash and the identifiers it derives.
internal struct IdentifierVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case handshakeHashHex = "handshake_hash_hex"
    case name = "name"
    case pairIDHex = "pair_id_hex"
    case sessionIDHex = "session_id_hex"
  }

  internal let name: String
  internal let handshakeHashHex: String
  internal let pairIDHex: String
  internal let sessionIDHex: String
}
