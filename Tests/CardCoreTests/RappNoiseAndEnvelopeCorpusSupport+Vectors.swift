// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappNoiseAndEnvelopeCorpusSupport {
  // MARK: Nested Types

  private enum NoiseCorpusKeys: String, CodingKey {
    case noiseHandshake = "noise_handshake"
    case rejectedEnvelope = "rejected_envelope"
  }

  private enum NoiseVectorKeys: String, CodingKey {
    case grantsHashHex = "grants_hash_hex"
    case handshakeHashHex = "handshake_hash_hex"
    case initiatorStaticPublicHex = "initiator_static_public_hex"
    case messagesHex = "messages_hex"
    case name = "name"
    case offerHashHex = "offer_hash_hex"
    case pairIDHex = "pair_id_hex"
    case prologueHex = "prologue_hex"
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

  private enum RejectedEnvelopeVectorKeys: String, CodingKey {
    case canonicalCBORHex = "canonical_cbor_hex"
    case error = "error"
    case name = "name"
  }

  internal struct Corpus: Decodable {
    // MARK: Properties

    internal let noiseHandshake: [NoiseVector]
    internal let rejectedEnvelope: [RejectedEnvelopeVector]

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: NoiseCorpusKeys.self)
      noiseHandshake = try container.decode([NoiseVector].self, forKey: .noiseHandshake)
      rejectedEnvelope = try container.decode(
        [RejectedEnvelopeVector].self, forKey: .rejectedEnvelope)
    }
  }

  internal struct NoiseVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let suite: String
    internal let transportProfile: String
    internal let handshakeHashHex: String
    internal let initiatorStaticPublicHex: String
    internal let responderStaticPublicHex: String
    internal let messagesHex: [String]
    internal let prologueHex: String
    internal let pairIDHex: String
    internal let sessionIDHex: String
    internal let offerHashHex: String?
    internal let grantsHashHex: String?
    internal let testOnlyInitiatorEphemeralPrivateHex: String
    internal let testOnlyInitiatorStaticPrivateHex: String
    internal let testOnlyPairingSecretHex: String?
    internal let testOnlyResponderEphemeralPrivateHex: String
    internal let testOnlyResponderStaticPrivateHex: String

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: NoiseVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      suite = try container.decode(String.self, forKey: .suite)
      transportProfile = try container.decode(String.self, forKey: .transportProfile)
      handshakeHashHex = try container.decode(String.self, forKey: .handshakeHashHex)
      initiatorStaticPublicHex = try container.decode(
        String.self, forKey: .initiatorStaticPublicHex)
      responderStaticPublicHex = try container.decode(
        String.self, forKey: .responderStaticPublicHex)
      messagesHex = try container.decode([String].self, forKey: .messagesHex)
      prologueHex = try container.decode(String.self, forKey: .prologueHex)
      pairIDHex = try container.decode(String.self, forKey: .pairIDHex)
      sessionIDHex = try container.decode(String.self, forKey: .sessionIDHex)
      offerHashHex = try container.decodeIfPresent(String.self, forKey: .offerHashHex)
      grantsHashHex = try container.decodeIfPresent(String.self, forKey: .grantsHashHex)
      testOnlyInitiatorEphemeralPrivateHex = try container.decode(
        String.self, forKey: .testOnlyInitiatorEphemeralPrivateHex)
      testOnlyInitiatorStaticPrivateHex = try container.decode(
        String.self, forKey: .testOnlyInitiatorStaticPrivateHex)
      testOnlyPairingSecretHex = try container.decodeIfPresent(
        String.self, forKey: .testOnlyPairingSecretHex)
      testOnlyResponderEphemeralPrivateHex = try container.decode(
        String.self, forKey: .testOnlyResponderEphemeralPrivateHex)
      testOnlyResponderStaticPrivateHex = try container.decode(
        String.self, forKey: .testOnlyResponderStaticPrivateHex)
    }
  }

  internal struct RejectedEnvelopeVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let canonicalCBORHex: String
    internal let error: String

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: RejectedEnvelopeVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      canonicalCBORHex = try container.decode(String.self, forKey: .canonicalCBORHex)
      error = try container.decode(String.self, forKey: .error)
    }
  }
}
