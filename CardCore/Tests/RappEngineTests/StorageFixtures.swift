// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Distinct filler bytes, so a field encoded in place of another shows up as
/// a different byte rather than a coincidental match.
private let fillerOfferIdentifier: UInt8 = 0x01
private let fillerPairIdentifier: UInt8 = 0x11
private let fillerLocalStaticPrivate: UInt8 = 0x33
private let fillerLocalStaticPublic: UInt8 = 0x44
private let fillerRemoteStaticPublic: UInt8 = 0x55
private let fillerGrantsHash: UInt8 = 0x66

/// Fixed times, so an encoding is reproducible run to run.
private let fixtureRecordCreatedAtMilliseconds: UInt64 = 1_700_000_000_000

/// The listener endpoint the stream binding carries, from the IPv4
/// documentation range (RFC 5737).
private let fixtureEndpoint = "192.0.2.1:47110"

internal func filler(_ byte: UInt8, _ count: Int) -> Data {
  Data(repeating: byte, count: count)
}

// MARK: - Unit 1: pairing offer

internal func makeOffer() throws -> PairingOffer {
  try PairingOffer.create(
    offerIdentifier: filler(fillerOfferIdentifier, OfferLimit.offerIdentifierSize),
    profiles: ["fi.refineid.card-status", "fi.refineid.authentication"],
    transportProfiles: [StreamProfile.name, RappBleGattProfile.name])
}

internal func makePairRecord() throws -> PairRecord {
  try PairRecord(
    pairIdentifier: filler(fillerPairIdentifier, PairRecordSize.pairIdentifier),
    role: .requester,
    localStaticPrivate: filler(fillerLocalStaticPrivate, PairRecordSize.staticKey),
    localStaticPublic: filler(fillerLocalStaticPublic, PairRecordSize.staticKey),
    remoteStaticPublic: filler(fillerRemoteStaticPublic, PairRecordSize.staticKey),
    grantsHash: filler(fillerGrantsHash, PairRecordSize.grantsHash),
    profiles: [.cardStatus, .authentication],
    transport: PairTransportBinding(
      profile: StreamProfile.name,
      candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
      parameters: ["endpoints": .array([.text(fixtureEndpoint)])]
    ),
    createdAtMilliseconds: fixtureRecordCreatedAtMilliseconds,
    storageConfirmed: true
  )
}

/// ``makePairRecord()`` as stored before the peer confirmed it (RAPP
/// v26.10.29 §4.3 item 4).
internal func makeUnconfirmedPairRecord() throws -> PairRecord {
  guard case .map(var map) = expectedPairRecordValue() else {
    throw PairRecordError.invalidInput
  }
  map["storage_confirmed"] = .boolean(false)
  return try PairRecord.decode(try WireValue.map(map).encoded())
}

/// The stored form of ``makePairRecord()``, assembled field by field from
/// the record's storage keys, so a renamed key or a changed value shows.
internal func expectedPairRecordValue() -> WireValue {
  .map([
    "format_version": .unsigned(pairRecordFormatVersion),
    "pair_id": .bytes(filler(fillerPairIdentifier, PairRecordSize.pairIdentifier)),
    "role": .text(EndpointRole.requester.rawValue),
    "local_static_private": .bytes(filler(fillerLocalStaticPrivate, PairRecordSize.staticKey)),
    "local_static_public": .bytes(filler(fillerLocalStaticPublic, PairRecordSize.staticKey)),
    "remote_static_public": .bytes(filler(fillerRemoteStaticPublic, PairRecordSize.staticKey)),
    "grants_hash": .bytes(filler(fillerGrantsHash, PairRecordSize.grantsHash)),
    "profiles": .array([
      .text(ProfileName.cardStatus.rawValue), .text(ProfileName.authentication.rawValue),
    ]),
    "transport_profile": .text(StreamProfile.name),
    "candidate_id": .text(TransportRegistry.streamCandidateIdentifier),
    "transport_parameters": .map(["endpoints": .array([.text(fixtureEndpoint)])]),
    "created_at_ms": .unsigned(fixtureRecordCreatedAtMilliseconds),
    "storage_confirmed": .boolean(true),
    "forgotten_at_ms": .null,
    "last_session_at_ms": .null,
  ])
}
