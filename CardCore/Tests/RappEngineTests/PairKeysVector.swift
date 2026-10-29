// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.29 §2.2.1 and §4.3).

internal struct PairKeysVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case custodianStaticPrivateHex = "custodian_static_private_hex"
    case discoveryKeyHex = "discovery_key_hex"
    case name = "name"
    case pairIDHex = "pair_id_hex"
    case requesterStaticPrivateHex = "requester_static_private_hex"
    case routingKeyHex = "routing_key_hex"
    case sharedSecretHex = "shared_secret_hex"
  }

  internal let name: String
  internal let pairIDHex: String
  internal let custodianStaticPrivateHex: String
  internal let requesterStaticPrivateHex: String
  internal let sharedSecretHex: String
  internal let discoveryKeyHex: String
  internal let routingKeyHex: String
}
