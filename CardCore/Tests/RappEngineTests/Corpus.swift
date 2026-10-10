// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored conformance corpus.
internal struct Corpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case cpaceKc2 = "cpace_kc2"
    case deterministicCBOR = "deterministic_cbor"
    case discoveryHint = "discovery_hint"
    case format = "format"
    case grantEnforcement = "grant_enforcement"
    case grantsHash = "grants_hash"
    case identifierDerivation = "identifier_derivation"
    case noiseHandshake = "noise_handshake"
    case pairingOffer = "pairing_offer"
    case protocolDocumentVersion = "protocol_document_version"
    case rejectedCBOR = "rejected_cbor"
    case rejectedEnvelope = "rejected_envelope"
    case requestHash = "request_hash"
    case sequenceGuard = "sequence_guard"
    case streamRendezvous = "stream_rendezvous"
    case wireVersion = "wire_version"
  }

  internal let format: String
  internal let protocolDocumentVersion: String
  internal let deterministicCBOR: [CBORVector]
  internal let rejectedCBOR: [RejectedCBORVector]
  internal let rejectedEnvelope: [RejectedEnvelopeVector]
  internal let wireVersion: [WireVersionVector]
  internal let sequenceGuard: [SequenceGuardVector]
  internal let grantEnforcement: [GrantEnforcementVector]
  internal let grantsHash: [GrantsVector]
  internal let requestHash: [RequestVector]
  internal let identifierDerivation: [IdentifierVector]
  internal let streamRendezvous: [StreamRendezvousVector]
  internal let noiseHandshake: [NoiseVector]
  internal let pairingOffer: [PairingOfferVector]
  internal let cpaceKc2: [CpaceKc2Vector]
  internal let discoveryHint: [DiscoveryHintVector]
}
