// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One `pairing_offer` corpus vector: an offer's exact bootstrap bytes.
internal struct PairingOfferVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case encodedHex = "encoded_hex"
    case encodedLength = "encoded_length"
    case name = "name"
    case offerHashHex = "offer_hash_hex"
    case offerIdHex = "offer_id_hex"
    case profiles = "profiles"
    case transportProfiles = "transport_profiles"
  }

  internal let name: String
  internal let offerIdHex: String
  internal let profiles: [String]
  internal let transportProfiles: [String]
  internal let encodedHex: String
  internal let encodedLength: Int
  internal let offerHashHex: String
}
