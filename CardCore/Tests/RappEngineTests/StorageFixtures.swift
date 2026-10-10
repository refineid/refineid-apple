// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Distinct filler bytes, so a field encoded in place of another shows up as
/// a different byte rather than a coincidental match.
private let fillerOfferIdentifier: UInt8 = 0x01
private let fillerPairIdentifier: UInt8 = 0x11
private let fillerRendezvousToken: UInt8 = 0x22
private let fillerLocalStaticPrivate: UInt8 = 0x33
private let fillerLocalStaticPublic: UInt8 = 0x44
private let fillerRemoteStaticPublic: UInt8 = 0x55
private let fillerGrantsHash: UInt8 = 0x66

/// Fixed times, so an encoding is reproducible run to run.
private let fixtureRecordCreatedAtMilliseconds: UInt64 = 1_700_000_000_000

internal func filler(_ byte: UInt8, _ count: Int) -> Data {
  Data(repeating: byte, count: count)
}

// MARK: - Unit 1: pairing offer

internal func makeOffer() throws -> PairingOffer {
  try PairingOffer.create(
    offerIdentifier: filler(fillerOfferIdentifier, OfferLimit.offerIdentifierSize),
    profiles: ["fi.refineid.card-status.v1", "fi.refineid.authentication.v1"],
    transportProfiles: ["fi.refineid.stream.v1", "apple-peer-v1"])
}

internal func makePairRecord() throws -> PairRecord {
  try PairRecord(
    pairIdentifier: filler(fillerPairIdentifier, PairRecordSize.pairIdentifier),
    rendezvousToken: filler(fillerRendezvousToken, PairRecordSize.rendezvousToken),
    role: .requester,
    localStaticPrivate: filler(fillerLocalStaticPrivate, PairRecordSize.staticKey),
    localStaticPublic: filler(fillerLocalStaticPublic, PairRecordSize.staticKey),
    remoteStaticPublic: filler(fillerRemoteStaticPublic, PairRecordSize.staticKey),
    grantsHash: filler(fillerGrantsHash, PairRecordSize.grantsHash),
    profiles: [.cardStatus, .authentication],
    transport: PairTransportBinding(
      profile: "fi.refineid.stream.v1",
      candidateIdentifier: "stream-1",
      parameters: ["endpoints": .array([.text("192.0.2.1:47110")])]
    ),
    createdAtMilliseconds: fixtureRecordCreatedAtMilliseconds
  )
}
