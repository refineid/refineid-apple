// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One fixed handshake transcript and its keys.
internal struct NoiseVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case initiatorToResponderKeyHex = "c1_initiator_to_responder_hex"
    case responderToInitiatorKeyHex = "c2_responder_to_initiator_hex"
    case grantsHashHex = "grants_hash_hex"
    case handshakeHashHex = "handshake_hash_hex"
    case initiatorStaticPublicHex = "initiator_static_public_hex"
    case messagesHex = "messages_hex"
    case name = "name"
    case offerHashHex = "offer_hash_hex"
    case pairIDHex = "pair_id_hex"
    case prologueHex = "prologue_hex"
    case rendezvousTokenHex = "rendezvous_token_hex"
    case responderStaticPublicHex = "responder_static_public_hex"
    case sessionIDHex = "session_id_hex"
    case suite = "suite"
    case testOnlyInitiatorEphemeralPrivateHex = "test_only_initiator_ephemeral_private_hex"
    case testOnlyInitiatorStaticPrivateHex = "test_only_initiator_static_private_hex"
    case testOnlyPairingSecretHex = "test_only_pairing_secret_hex"
    case testOnlyResponderEphemeralPrivateHex = "test_only_responder_ephemeral_private_hex"
    case testOnlyResponderStaticPrivateHex = "test_only_responder_static_private_hex"
    case transportProfile = "transport_profile"
  }

  internal let name: String
  internal let suite: String
  internal let transportProfile: String
  internal let prologueHex: String
  internal let handshakeHashHex: String
  internal let messagesHex: [String]
  internal let initiatorStaticPublicHex: String
  internal let responderStaticPublicHex: String
  internal let pairIDHex: String
  internal let sessionIDHex: String
  internal let rendezvousTokenHex: String?
  internal let offerHashHex: String?
  internal let grantsHashHex: String?
  internal let initiatorToResponderKeyHex: String?
  internal let responderToInitiatorKeyHex: String?
  internal let testOnlyPairingSecretHex: String?
  internal let testOnlyInitiatorStaticPrivateHex: String
  internal let testOnlyResponderStaticPrivateHex: String
  internal let testOnlyInitiatorEphemeralPrivateHex: String
  internal let testOnlyResponderEphemeralPrivateHex: String
}
