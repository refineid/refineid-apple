// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import RappEngine
import XCTest

/// Proves that session discovery publishes nothing stable, that rotating
/// hints and withdrawals name only their own pairing, and that a dial is
/// routed only by routing its pairing's keys produce (RAPP v26.10.18
/// §2.2.1, §4.3 and §4.5).
internal final class StreamSessionDiscoveryTests: XCTestCase {
  /// The two halves of one pairing, plus the requester half of another.
  private struct Pairing {
    let custodian: RappPairRecord
    let requester: RappPairRecord
  }

  /// A pair vault that only remembers which pairing it was told to revoke.
  private final class RecordingVault: RappPairVault, @unchecked Sendable {
    private(set) var revoked: [Data] = []

    func insertDeviceOnly(pairId _: Data, record _: Data) {
      // No record is kept.
    }

    func replaceDeviceOnly(pairId _: Data, record _: Data) {
      // No record is kept.
    }

    func loadDeviceOnly(pairId _: Data) -> Data? {
      nil
    }

    func revokeDeviceOnly(pairId: Data, revokedAtMs _: UInt64) {
      revoked.append(pairId)
    }

    func isRevoked(pairId: Data) -> Bool {
      revoked.contains(pairId)
    }
  }

  /// A fixed instant inside one hint window.
  private static let instant = Date(timeIntervalSince1970: 1_800_000_000)
  private static let hintHexLength = 16
  private static let ephemeralNamePattern = "^refineid-[0-9a-f]{8}$"
  private static let instance = "refineid-7f2a1c84"

  private static func pairing() throws -> Pairing {
    let custodianKey = Curve25519.KeyAgreement.PrivateKey()
    let requesterKey = Curve25519.KeyAgreement.PrivateKey()
    return Pairing(
      custodian: try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: custodianKey.rawRepresentation,
        localStaticPublic: custodianKey.publicKey.rawRepresentation,
        localRole: .proxy,
        remotePublicKey: requesterKey.publicKey.rawRepresentation),
      requester: try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: requesterKey.rawRepresentation,
        localStaticPublic: requesterKey.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: custodianKey.publicKey.rawRepresentation))
  }

  private static func candidate(_ record: RappPairRecord, at date: Date) throws
    -> RappAnnouncementCandidate
  {
    RappAnnouncementCandidate(
      hint: try record.discoveryHint(unixTimeSeconds: StreamRendezvousName.unixTime(date)),
      lastUsedMs: 0)
  }

  internal func testEphemeralNamesAreRandom() {
    let first = StreamRendezvousName.ephemeralName()
    let second = StreamRendezvousName.ephemeralName()
    XCTAssertNotNil(first.range(of: Self.ephemeralNamePattern, options: .regularExpression))
    XCTAssertNotEqual(first, second)
  }

  internal func testSessionRecordCarriesOnlyHints() throws {
    let pair = try Self.pairing()
    let record = StreamRendezvousName.sessionRecord(
      candidates: [try Self.candidate(pair.custodian, at: Self.instant)],
      retentions: [], instance: Self.instance, at: Self.instant)
    XCTAssertEqual(record["v"], "1")
    XCTAssertEqual(record["mode"], "session")
    XCTAssertEqual(record["hints"]?.count, Self.hintHexLength)
    XCTAssertEqual(Set(record.keys), ["v", "mode", "hints"])
  }

  internal func testHintsNameOnlyTheirOwnPairingWithinAdjacentWindows() throws {
    let pair = try Self.pairing()
    let other = try Self.pairing()
    let window = TimeInterval(StreamRendezvousName.hintEpochSeconds)
    let record = StreamRendezvousName.sessionRecord(
      candidates: [try Self.candidate(pair.custodian, at: Self.instant)],
      retentions: [], instance: Self.instance, at: Self.instant)
    XCTAssertTrue(
      StreamRendezvousName.sessionRecord(record, holds: pair.requester, at: Self.instant))
    XCTAssertTrue(
      StreamRendezvousName.sessionRecord(
        record, holds: pair.requester, at: Self.instant.addingTimeInterval(window)))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(
        record, holds: pair.requester, at: Self.instant.addingTimeInterval(2 * window)))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(record, holds: other.requester, at: Self.instant))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(
        StreamRendezvousName.pairingAttributes, holds: pair.requester, at: Self.instant))
  }

  internal func testSessionRecordAnnouncesRevokedPairings() throws {
    let kept = try Self.pairing()
    let forgotten = try Self.pairing()
    let vault = RecordingVault()
    let revokedAt = UInt64(Self.instant.timeIntervalSince1970) * 1_000
    let retention = try XCTUnwrap(
      try forgotten.custodian.revoke(vault: vault, revokedAtMs: revokedAt))
    let record = StreamRendezvousName.sessionRecord(
      candidates: [try Self.candidate(kept.custodian, at: Self.instant)],
      retentions: [retention], instance: Self.instance, at: Self.instant)
    XCTAssertEqual(Set(record.keys), ["v", "mode", "hints", "revoked"])
    XCTAssertEqual(record["revoked"]?.split(separator: ",").count, 8)
    XCTAssertTrue(
      StreamRendezvousName.sessionRecord(
        record, instance: Self.instance, revokes: forgotten.requester, at: Self.instant))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(
        record, instance: Self.instance, revokes: kept.requester, at: Self.instant))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(
        record, instance: "refineid-b3d90e15", revokes: forgotten.requester, at: Self.instant))
    XCTAssertTrue(
      StreamRendezvousName.sessionRecord(record, holds: kept.requester, at: Self.instant))
    XCTAssertEqual(vault.revoked, [forgotten.custodian.metadata().pairId])
  }

  internal func testAtMostFourHintsArePublished() throws {
    let candidates = try (0..<6).map { _ in
      try Self.candidate(Self.pairing().custodian, at: Self.instant)
    }
    let record = StreamRendezvousName.sessionRecord(
      candidates: candidates, retentions: [], instance: Self.instance, at: Self.instant)
    XCTAssertEqual(record["hints"]?.split(separator: ",").count, 4)
  }

  internal func testFreshRoutingReachesOnlyItsPairingOnce() throws {
    let pair = try Self.pairing()
    let other = try Self.pairing()
    let profile = rappStreamProfileName()
    let router = RappSessionRouter()
    let records = [other.custodian, pair.custodian]
    let first = try pair.requester.sessionPreamble(transportProfile: profile)
    let second = try pair.requester.sessionPreamble(transportProfile: profile)
    XCTAssertNotEqual(first, second, "every dial draws fresh routing")
    XCTAssertEqual(
      router.route(transportProfile: profile, preamble: first, records: records),
      .session(index: 1))
    XCTAssertEqual(
      router.route(transportProfile: profile, preamble: first, records: records), .refuse,
      "a replayed preamble is refused")
    XCTAssertEqual(
      router.route(transportProfile: profile, preamble: second, records: [other.custodian]),
      .refuse)
    XCTAssertEqual(
      router.route(transportProfile: profile, preamble: Data("noise".utf8), records: records),
      .refuse)
    XCTAssertEqual(
      router.route(
        transportProfile: profile,
        preamble: try rappPairingPreamble(transportProfile: profile), records: records),
      .pairing)
  }

  internal func testWithdrawalNamesItsPairingOnItsInstanceOnly() throws {
    let pair = try Self.pairing()
    let other = try Self.pairing()
    let time = StreamRendezvousName.unixTime(Self.instant)
    let hint = try pair.custodian.withdrawalHint(instance: Self.instance, unixTimeSeconds: time)
    let record = try XCTUnwrap(
      StreamRendezvousName.withdrawnRecord(
        candidates: [RappAnnouncementCandidate(hint: hint, lastUsedMs: 0)]))
    XCTAssertEqual(record["withdrawn"]?.split(separator: ",").count, 8)
    XCTAssertTrue(
      StreamRendezvousName.withdrawnRecord(
        record, instance: Self.instance, withdraws: pair.requester, at: Self.instant))
    XCTAssertFalse(
      StreamRendezvousName.withdrawnRecord(
        record, instance: "refineid-b3d90e15", withdraws: pair.requester, at: Self.instant))
    XCTAssertFalse(
      StreamRendezvousName.withdrawnRecord(
        record, instance: Self.instance, withdraws: other.requester, at: Self.instant))
  }
}
