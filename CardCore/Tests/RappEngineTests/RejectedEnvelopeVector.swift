// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One envelope the schema must refuse.
internal struct RejectedEnvelopeVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case canonicalCBORHex = "canonical_cbor_hex"
    case error = "error"
    case name = "name"
  }

  internal let name: String
  internal let canonicalCBORHex: String
  internal let error: String
}
