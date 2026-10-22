// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.22 §2.2.1 and §4.3).

internal struct RoutingLookupVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case custodianPairIDsHex = "custodian_pair_ids_hex"
    case expectedIndex = "expected_index"
    case name = "name"
    case routingHex = "routing_hex"
    case transportProfile = "transport_profile"
  }

  internal let name: String
  internal let transportProfile: String
  internal let routingHex: String
  internal let custodianPairIDsHex: [String]
  internal let expectedIndex: Int?
}
