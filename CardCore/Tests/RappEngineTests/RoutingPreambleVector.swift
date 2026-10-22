// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.22 §2.2.1 and §4.3).

internal struct RoutingPreambleVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case encodedHex = "encoded_hex"
    case name = "name"
    case nonceHex = "nonce_hex"
    case purpose = "purpose"
    case routingTagHex = "routing_tag_hex"
    case transportProfile = "transport_profile"
  }

  internal let name: String
  internal let transportProfile: String
  internal let purpose: String
  internal let nonceHex: String?
  internal let routingTagHex: String?
  internal let encodedHex: String
}
