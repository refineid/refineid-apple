// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.1 BLE offer and bootstrap (section 4.2)")
internal struct BleOfferTests {
  private static let code = "7KX4M9"
  private static let profiles = [
    "fi.refineid.card-status.v1", "fi.refineid.authentication.v1",
    "fi.refineid.document-signing.v1",
  ]
  /// The encoded length section 4.2 states for the KC2 offer.
  private static let specifiedOfferLength = 400

  private static func custodian() throws -> RappPairingBridge {
    try RappPairingBridge.bleOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: profiles, startedAtMonotonicMs: 0)
  }

  @Test("The bootstrap offer is the 400-byte KC2 offer with a random identifier")
  internal func offerShape() throws {
    let encoded = try Self.custodian().encodedOffer()
    #expect(encoded.count == Self.specifiedOfferLength)
    let offer = try PairingOffer.decode(encoded)
    #expect(offer.offerLifetimeMilliseconds == RappBleGattProfile.offerLifetimeMilliseconds)
    #expect(offer.suites == [RappCpaceConstants.kc2Suite])
    #expect(offer.transports.map(\.profile) == [RappBleGattProfile.name])
    #expect(offer.transports.map(\.candidateIdentifier) == [RappBleGattProfile.candidateId])
    #expect(try Self.custodian().encodedOffer() != encoded, "a fresh identifier per offer")
  }

  @Test("A requester that read the bootstrap offer completes the ceremony")
  internal func ceremonyOverBootstrap() throws {
    let custodian = try Self.custodian()
    let requester = try RappPairingBridge.bootstrapOffer(
      encodedOffer: try custodian.encodedOffer(), pairingCode: Self.code,
      startedAtMonotonicMs: 0)
    let now: UInt64 = 1_000
    let candidate = RappBleGattProfile.candidateId
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
    let requesterRecord = try requester.finishPairing(createdAtMs: 0, nowMonotonicMs: now)
    let custodianRecord = try custodian.finishPairing(createdAtMs: 0, nowMonotonicMs: now)
    #expect(requesterRecord.metadata().pairId == custodianRecord.metadata().pairId)
  }

  @Test("A wrong code fails CPace against a bootstrap offer")
  internal func wrongCodeFails() throws {
    let custodian = try Self.custodian()
    let requester = try RappPairingBridge.bootstrapOffer(
      encodedOffer: try custodian.encodedOffer(), pairingCode: "7KX4M8",
      startedAtMonotonicMs: 0)
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

  @Test("An offer without the BLE candidate or with a malformed body is refused")
  internal func foreignOfferRefused() throws {
    let streamOffer = try RappPairingBridge.codeOffer(
      role: .proxy, pairingCode: Self.code, profiles: Self.profiles,
      transports: [
        RappTransportCandidate(
          profile: rappStreamProfileName(), candidateId: "stream-1", parametersCbor: Data())
      ],
      offerTtlMs: RappBleGattProfile.offerLifetimeMilliseconds, startedAtMonotonicMs: 0)
    #expect(throws: RappBindingError.InvalidInput) {
      try RappPairingBridge.bootstrapOffer(
        encodedOffer: try streamOffer.encodedOffer(), pairingCode: Self.code,
        startedAtMonotonicMs: 0)
    }
    #expect(throws: RappBindingError.InvalidInput) {
      try RappPairingBridge.bootstrapOffer(
        encodedOffer: Data([0xA0]), pairingCode: Self.code, startedAtMonotonicMs: 0)
    }
    #expect(throws: RappBindingError.InvalidInput) {
      try RappPairingBridge.bleOffer(
        pairingCode: Self.code, offerId: Data(count: 16), profiles: Self.profiles,
        startedAtMonotonicMs: 0)
    }
  }
}
