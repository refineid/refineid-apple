// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.10 §2.2.1 and §4.3).

internal struct WithdrawalAcceptanceVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case expected = "expected"
    case name = "name"
    case publishedCounter = "published_counter"
    case publishedInstance = "published_instance"
    case requesterCounter = "requester_counter"
    case requesterInstance = "requester_instance"
    case requesterPairIDHex = "requester_pair_id_hex"
  }

  internal let name: String
  internal let publishedInstance: String
  internal let publishedCounter: UInt64
  internal let requesterInstance: String
  internal let requesterCounter: UInt64
  internal let requesterPairIDHex: String
  internal let expected: String
}
