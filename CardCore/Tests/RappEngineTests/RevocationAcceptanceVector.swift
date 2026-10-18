// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a requester accepts a published hint for its own instance and
/// epoch.
internal struct RevocationAcceptanceVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case expected = "expected"
    case name = "name"
    case publishedEpoch = "published_epoch"
    case publishedInstance = "published_instance"
    case requesterEpoch = "requester_epoch"
    case requesterInstance = "requester_instance"
    case requesterPairIDHex = "requester_pair_id_hex"
  }

  internal let name: String
  internal let publishedInstance: String
  internal let publishedEpoch: UInt64
  internal let requesterInstance: String
  internal let requesterEpoch: UInt64
  internal let requesterPairIDHex: String
  internal let expected: String
}
