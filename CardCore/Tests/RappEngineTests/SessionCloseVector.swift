// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.18 §2.2.1 and §4.3).

internal struct SessionCloseVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case bodyCborHex = "body_cbor_hex"
    case lastReceivedSequence = "last_received_sequence"
    case name = "name"
    case reason = "reason"
  }

  internal let name: String
  internal let reason: String
  internal let lastReceivedSequence: UInt64
  internal let bodyCborHex: String
}
