// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One typed request and the digest it binds to.
internal struct RequestVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case action = "action"
    case context = "context"
    case name = "name"
    case operationIDHex = "operation_id_hex"
    case payload = "payload"
    case preimageCBORHex = "preimage_cbor_hex"
    case profile = "profile"
    case pairIDHex = "pair_id_hex"
    case sha256Hex = "sha256_hex"
  }

  internal let name: String
  internal let pairIDHex: String
  internal let operationIDHex: String
  internal let profile: String
  internal let action: String
  internal let context: CorpusValue
  internal let payload: CorpusValue
  internal let preimageCBORHex: String
  internal let sha256Hex: String
}
