// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored withdrawal corpus (RAPP v26.10.21 §4.5).

internal struct SessionCloseVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case bodyCborHex = "body_cbor_hex"
    case name = "name"
    case reason = "reason"
  }

  internal let name: String
  internal let reason: String
  internal let bodyCborHex: String
}
