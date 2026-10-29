// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.29 offer bootstrap on BLE and stream (section 4.2)")
internal struct BootstrapOfferTests {
  private static let code = "7KX4M9"
  private static let profiles = [
    "fi.refineid.card-status", "fi.refineid.authentication",
    "fi.refineid.document-signing",
  ]

  private static func custodian(
    transportProfiles: [String] = [RappBleGattProfile.name]
  ) throws -> RappPairingBridge {
    try RappPairingBridge.custodianOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: profiles, transportProfiles: transportProfiles, startedAtMonotonicMs: 0)
  }

  /// Both endpoints store their record and confirm it to each other,
  /// which makes the pairing active on both.
  private static func exchangeStorage(
    requester: RappPairingBridge, custodian: RappPairingBridge, now: UInt64
  ) throws -> (RappPairRecord, RappPairRecord) {
    _ = try requester.buildPairRecord(createdAtMs: 0, nowMonotonicMs: now)
    _ = try custodian.buildPairRecord(createdAtMs: 0, nowMonotonicMs: now)
    let requesterStored = try requester.sendStored(nowMonotonicMs: now)
    let custodianStored = try custodian.sendStored(nowMonotonicMs: now)
    try custodian.receiveStored(bytes: requesterStored, nowMonotonicMs: now)
    try requester.receiveStored(bytes: custodianStored, nowMonotonicMs: now)
    let requesterRecord = try #require(try requester.activatePairing(nowMonotonicMs: now))
    let custodianRecord = try #require(try custodian.activatePairing(nowMonotonicMs: now))
    return (requesterRecord, custodianRecord)
  }

  @Test("The bootstrap offer is the corpus's BLE KC2 offer size with a random identifier")
  internal func offerShape() throws {
    let encoded = try Self.custodian().encodedOffer()
    let pinned = try #require(
      try CorpusFile.conformance(filePath: #filePath).pairingOffer.first { vector in
        vector.transportProfiles == [RappBleGattProfile.name]
      })
    #expect(encoded.count == pinned.encodedLength)
    let offer = try PairingOffer.decode(encoded)
    #expect(offer.suites == [RappCpaceConstants.kc2Suite])
    #expect(offer.transports.map(\.profile) == [RappBleGattProfile.name])
    #expect(offer.transports.map(\.candidateIdentifier) == [RappBleGattProfile.candidateId])
    #expect(try Self.custodian().encodedOffer() != encoded, "a fresh identifier per offer")
  }

  @Test(
    "A requester that read the bootstrap offer completes the ceremony on either transport",
    arguments: [RappBleGattProfile.name, StreamProfile.name])
  internal func ceremonyOverBootstrap(transportProfile: String) throws {
    let custodian = try Self.custodian(
      transportProfiles: [RappBleGattProfile.name, StreamProfile.name])
    let requester = try RappPairingBridge.bootstrapOffer(
      encodedOffer: try custodian.encodedOffer(), transportProfile: transportProfile,
      pairingCode: Self.code, startedAtMonotonicMs: 0)
    let now: UInt64 = 1_000
    let candidate = try #require(rappCandidateIdentifier(transportProfile: transportProfile))
    let random = { randomBytes(RappCpaceConstants.wideScalarSize) }
    try requester.beginCpace(candidateId: candidate, randomBytes64: random(), nowMonotonicMs: now)
    try custodian.beginCpace(candidateId: candidate, randomBytes64: random(), nowMonotonicMs: now)
    try custodian.readCpaceFrame(
      bytes: try requester.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try requester.readCpaceFrame(
      bytes: try custodian.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try custodian.readCpaceFrame(
      bytes: try requester.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try custodian.readHandshakeFrame(
      bytes: try requester.writeHandshakeFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try requester.readHandshakeFrame(
      bytes: try custodian.writeHandshakeFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try custodian.readHandshakeFrame(
      bytes: try requester.writeHandshakeFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try requester.enterConfirmation(nowMonotonicMs: now)
    try custodian.enterConfirmation(nowMonotonicMs: now)
    _ = try custodian.receiveHello(
      bytes: try requester.sendHello(displayName: "Mac", platform: "macOS", nowMonotonicMs: now),
      nowMonotonicMs: now)
    _ = try requester.receiveHello(
      bytes: try custodian.sendHello(displayName: "iPhone", platform: "iOS", nowMonotonicMs: now),
      nowMonotonicMs: now)
    let granted = try requester.receiveConfirmation(
      bytes: try custodian.sendConfirmation(grantedProfiles: Self.profiles, nowMonotonicMs: now),
      nowMonotonicMs: now)
    _ = try custodian.receiveConfirmation(
      bytes: try requester.sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now),
      nowMonotonicMs: now)
    let (requesterRecord, custodianRecord) = try Self.exchangeStorage(
      requester: requester, custodian: custodian, now: now)
    #expect(requesterRecord.metadata().storageConfirmed)
    #expect(custodianRecord.metadata().storageConfirmed)
    #expect(requesterRecord.metadata().pairId == custodianRecord.metadata().pairId)
  }

  @Test("A wrong code fails CPace against a bootstrap offer")
  internal func wrongCodeFails() throws {
    let custodian = try Self.custodian()
    let requester = try RappPairingBridge.bootstrapOffer(
      encodedOffer: try custodian.encodedOffer(), transportProfile: RappBleGattProfile.name,
      pairingCode: "7KX4M8", startedAtMonotonicMs: 0)
    let candidate = RappBleGattProfile.candidateId
    let random = { randomBytes(RappCpaceConstants.wideScalarSize) }
    try requester.beginCpace(candidateId: candidate, randomBytes64: random(), nowMonotonicMs: 1)
    try custodian.beginCpace(candidateId: candidate, randomBytes64: random(), nowMonotonicMs: 1)
    try custodian.readCpaceFrame(
      bytes: try requester.writeCpaceFrame(nowMonotonicMs: 1), nowMonotonicMs: 1)
    #expect(throws: RappBindingError.ProtocolFailure) {
      try requester.readCpaceFrame(
        bytes: try custodian.writeCpaceFrame(nowMonotonicMs: 1), nowMonotonicMs: 1)
    }
  }

  @Test("An offer without the connection's transport or with a malformed body is refused")
  internal func foreignOfferRefused() throws {
    let streamOffer = try Self.custodian(transportProfiles: [rappStreamProfileName()])
    #expect(throws: RappBindingError.InvalidInput) {
      try RappPairingBridge.bootstrapOffer(
        encodedOffer: try streamOffer.encodedOffer(), transportProfile: RappBleGattProfile.name,
        pairingCode: Self.code, startedAtMonotonicMs: 0)
    }
    #expect(throws: RappBindingError.InvalidInput) {
      try RappPairingBridge.bootstrapOffer(
        encodedOffer: Data([0xA0]), transportProfile: RappBleGattProfile.name,
        pairingCode: Self.code, startedAtMonotonicMs: 0)
    }
    #expect(throws: RappBindingError.InvalidInput) {
      try RappPairingBridge.custodianOffer(
        pairingCode: Self.code, offerId: Data(count: 16), profiles: Self.profiles,
        transportProfiles: [RappBleGattProfile.name], startedAtMonotonicMs: 0)
    }
    #expect(throws: RappBindingError.InvalidInput) {
      try RappPairingBridge.custodianOffer(
        pairingCode: Self.code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
        profiles: Self.profiles, transportProfiles: ["fi.example.unregistered"],
        startedAtMonotonicMs: 0)
    }
  }
}
