// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One CPace KC2 cross-implementation vector.
internal struct CpaceKc2Vector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case name = "name"
    case pairingCode = "pairing_code"
    case offerIdHex = "offer_id_hex"
    case offerHashHex = "offer_hash_hex"
    case contextHex = "context_hex"
    case generatorStringHex = "generator_string_hex"
    case testOnlyInitiatorRandomHex = "test_only_initiator_random_hex"
    case testOnlyResponderRandomHex = "test_only_responder_random_hex"
    case testOnlyInitiatorScalarHex = "test_only_initiator_scalar_hex"
    case testOnlyResponderScalarHex = "test_only_responder_scalar_hex"
    case yaHex = "ya_hex"
    case ybHex = "yb_hex"
    case transcriptHashHex = "transcript_hash_hex"
    case pskHex = "psk_hex"
    case stepTwoHex = "step2_hex"
    case stepThreeHex = "step3_hex"
  }

  internal let name: String
  internal let pairingCode: String
  internal let offerIdHex: String
  internal let offerHashHex: String
  internal let contextHex: String
  internal let generatorStringHex: String
  internal let testOnlyInitiatorRandomHex: String
  internal let testOnlyResponderRandomHex: String
  internal let testOnlyInitiatorScalarHex: String
  internal let testOnlyResponderScalarHex: String
  internal let yaHex: String
  internal let ybHex: String
  internal let transcriptHashHex: String
  internal let pskHex: String
  internal let stepTwoHex: String
  internal let stepThreeHex: String
}
