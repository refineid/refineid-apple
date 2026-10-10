// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One `cpace_kc2` corpus vector: a full KC2 exchange over one transport.
internal struct CpaceKc2Vector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case candidateIdentifier = "candidate_id"
    case contextHex = "context_hex"
    case contextLength = "context_length"
    case generatorHex = "generator_hex"
    case name = "name"
    case offerHashHex = "offer_hash_hex"
    case offerIdHex = "offer_id_hex"
    case pairingCode = "pairing_code"
    case stepOneHex = "step1_hex"
    case stepThreeHex = "step3_hex"
    case stepTwoHex = "step2_hex"
    case testOnlyInitiatorRandomHex = "test_only_initiator_random_hex"
    case testOnlyResponderRandomHex = "test_only_responder_random_hex"
    case transportProfile = "transport_profile"
  }

  internal let name: String
  internal let transportProfile: String
  internal let candidateIdentifier: String
  internal let pairingCode: String
  internal let offerIdHex: String
  internal let offerHashHex: String
  internal let contextHex: String
  internal let contextLength: Int
  internal let generatorHex: String
  internal let testOnlyInitiatorRandomHex: String
  internal let testOnlyResponderRandomHex: String
  internal let stepOneHex: String
  internal let stepTwoHex: String
  internal let stepThreeHex: String
}
