// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The corpus's synthetic pairing and the revocation key both endpoints
/// derive from it.
internal struct RevocationKeyVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case custodianStaticPrivateHex = "custodian_static_private_hex"
    case custodianStaticPublicHex = "custodian_static_public_hex"
    case name = "name"
    case pairIDHex = "pair_id_hex"
    case requesterStaticPrivateHex = "requester_static_private_hex"
    case requesterStaticPublicHex = "requester_static_public_hex"
    case revocationKeyHex = "revocation_key_hex"
    case sharedSecretHex = "shared_secret_hex"
  }

  internal let name: String
  internal let pairIDHex: String
  internal let custodianStaticPrivateHex: String
  internal let custodianStaticPublicHex: String
  internal let requesterStaticPrivateHex: String
  internal let requesterStaticPublicHex: String
  internal let sharedSecretHex: String
  internal let revocationKeyHex: String
}
