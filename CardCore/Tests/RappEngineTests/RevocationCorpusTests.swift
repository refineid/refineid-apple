// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

/// Replays the revocation corpus byte for byte (RAPP v26.10.18 §4.6).
@Suite("RAPP v26.10.18 revocation corpus")
internal struct RevocationCorpusTests {
  private static let accepted = "accepted"

  /// Fillers and sort keys drawn from a fixed pattern, so an assembled
  /// announcement is checked for its hints, not its order.
  private static let fixedByte: UInt8 = 0x5c

  private static func publicKey(_ privateHex: String) throws -> Data {
    let raw = try Data(hex: privateHex)
    return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
      .publicKey.rawRepresentation
  }

  private static func hex(_ key: SymmetricKey) -> String {
    key.withUnsafeBytes { Data($0) }.hex
  }

  /// The revocation key one endpoint derives for the pairing `pairIDHex`
  /// names, from its own static private key and its peer's public key.
  private static func derive(
    pairIDHex: String, localPrivateHex: String, remotePublic: Data
  ) throws -> SymmetricKey {
    let pairIdentifier = try Data(hex: pairIDHex)
    let localPrivate = try Data(hex: localPrivateHex)
    let derived = PairKeys.derive(
      pairIdentifier: pairIdentifier,
      localStaticPrivate: localPrivate,
      remoteStaticPublic: remotePublic,
      info: PairKeys.revocationInfo)
    return try #require(derived)
  }

  /// The custodian's revocation key from the corpus's synthetic pairing,
  /// checked against the requester's.
  private static func revocationKey(_ keys: RevocationKeyVector) throws -> RevocationKey {
    let custodianPublic = try publicKey(keys.custodianStaticPrivateHex)
    #expect(custodianPublic.hex == keys.custodianStaticPublicHex)
    let requesterPublic = try Data(hex: keys.requesterStaticPublicHex)
    let custodian = try derive(
      pairIDHex: keys.pairIDHex,
      localPrivateHex: keys.custodianStaticPrivateHex,
      remotePublic: requesterPublic)
    #expect(hex(custodian) == keys.revocationKeyHex)
    let requester = try derive(
      pairIDHex: keys.pairIDHex,
      localPrivateHex: keys.requesterStaticPrivateHex,
      remotePublic: custodianPublic)
    #expect(hex(requester) == keys.revocationKeyHex)
    return RevocationKey(key: custodian)
  }

  private static func instance(_ name: String) throws -> InstanceName {
    try #require(InstanceName(name))
  }

  /// `published` among seven fillers.
  private static func padded(_ published: Data) -> [Data] {
    var entries = [published]
    for index in 1..<RevokedAnnouncement.entryCount {
      entries.append(Data(repeating: UInt8(index), count: AnnouncementText.hintSize))
    }
    return entries
  }

  /// A custodian record over the corpus's synthetic pairing.
  private static func record(_ keys: RevocationKeyVector) throws -> PairRecord {
    let pairIdentifier = try Data(hex: keys.pairIDHex)
    let localPrivate = try Data(hex: keys.custodianStaticPrivateHex)
    let localPublic = try Data(hex: keys.custodianStaticPublicHex)
    let remotePublic = try Data(hex: keys.requesterStaticPublicHex)
    return try PairRecord(
      pairIdentifier: pairIdentifier,
      role: .proxy,
      localStaticPrivate: localPrivate,
      localStaticPublic: localPublic,
      remoteStaticPublic: remotePublic,
      grantsHash: Data(repeating: fixedByte, count: PairRecordSize.grantsHash),
      profiles: [.cardStatus],
      transport: PairTransportBinding(profile: "stream", candidateIdentifier: "stream-1"),
      createdAtMilliseconds: 0,
      storageConfirmed: true)
  }

  @Test("Revocation keys and hints match")
  internal func revocationHints() throws {
    let corpus = try CorpusFile.revocation(filePath: #filePath)
    #expect(corpus.protocolDocumentVersion == "26.10.18")
    let keys = try #require(corpus.revocationKey.first)
    let key = try Self.revocationKey(keys)
    for vector in corpus.revocationHint {
      let instance = try Self.instance(vector.instanceName)
      #expect(DiscoveryRecord.epoch(unixTimeSeconds: vector.unixTimeSeconds) == vector.epoch)
      #expect(
        key.hint(instance: instance, epoch: vector.epoch).hex == vector.revocationHintHex,
        "\(vector.name)")
    }
  }

  @Test("A published hint is accepted only for its instance and epoch window")
  internal func revocationAcceptance() throws {
    let corpus = try CorpusFile.revocation(filePath: #filePath)
    let keys = try #require(corpus.revocationKey.first)
    let key = try Self.revocationKey(keys)
    let custodianPublic = try Data(hex: keys.custodianStaticPublicHex)
    for vector in corpus.revocationAcceptance {
      let publishedInstance = try Self.instance(vector.publishedInstance)
      let published = key.hint(instance: publishedInstance, epoch: vector.publishedEpoch)
      let record = DiscoveryRecord.parse([
        (AnnouncementText.versionKey, AnnouncementText.version),
        (AnnouncementText.modeKey, "session"),
        ("revoked", AnnouncementText.encode(Self.padded(published))),
      ])
      let parsed = try #require(record, "\(vector.name)")
      let requesterKey: RevocationKey
      if vector.requesterPairIDHex == keys.pairIDHex {
        requesterKey = key
      } else {
        requesterKey = RevocationKey(
          key: try Self.derive(
            pairIDHex: vector.requesterPairIDHex,
            localPrivateHex: keys.requesterStaticPrivateHex,
            remotePublic: custodianPublic))
      }
      let requesterInstance = try Self.instance(vector.requesterInstance)
      let matched = requesterKey.matches(
        parsed, instance: requesterInstance, epoch: vector.requesterEpoch)
      #expect(matched == (vector.expected == Self.accepted), "\(vector.name)")
    }
  }

  @Test("Session records with revocations parse and match as the corpus says")
  internal func sessionRecords() throws {
    let corpus = try CorpusFile.revocation(filePath: #filePath)
    let keys = try #require(corpus.revocationKey.first)
    let key = try Self.revocationKey(keys)
    for vector in corpus.sessionRecord {
      let record = try #require(DiscoveryRecord.parse(vector.entries), "\(vector.name)")
      #expect(record.hints.map(\.hex) == vector.hintsHex, "\(vector.name)")
      let instanceName = try #require(vector.instanceName)
      let epoch = try #require(vector.requesterEpoch)
      let instance = try Self.instance(instanceName)
      let matched = key.matches(record, instance: instance, epoch: epoch)
      #expect(matched == (vector.expected == Self.accepted), "\(vector.name)")
    }
    for vector in corpus.malformedRecord {
      #expect(DiscoveryRecord.parse(vector.entries) == nil, "\(vector.name)")
    }
  }

  @Test("A retention is announced for thirty days from its revocation")
  internal func retentionWindow() throws {
    let corpus = try CorpusFile.revocation(filePath: #filePath)
    let keys = try #require(corpus.revocationKey.first)
    let record = try Self.record(keys)
    for vector in corpus.retentionWindow {
      let retention = try #require(
        RevocationRetention(record: record, revokedAtMilliseconds: vector.revokedAtMs))
      #expect(
        retention.announces(atMilliseconds: vector.nowMs) == vector.announced,
        "\(vector.name)")
      let encoded = try retention.encoded()
      let roundTrip = try RevocationRetention.decode(encoded)
      #expect(roundTrip.revokedAtMilliseconds == vector.revokedAtMs)
      #expect(roundTrip.pairIdentifier == retention.pairIdentifier)
    }
  }

  @Test("An announcement carries the eight most recently revoked pairings")
  internal func announcementSelection() throws {
    let corpus = try CorpusFile.revocation(filePath: #filePath)
    for vector in corpus.announcementSelection {
      var candidates: [AnnouncementCandidate] = []
      for candidate in vector.candidates {
        let hint = try Data(hex: candidate.hintHex)
        candidates.append(
          AnnouncementCandidate(hint: hint, lastUsedMilliseconds: candidate.revokedAtMs))
      }
      let assembled = RevokedAnnouncement.assemble(candidates) { count in
        Data(repeating: Self.fixedByte, count: count)
      }
      let announcement = try #require(assembled, "\(vector.name)")
      let announced = Set(vector.announcedHex)
      #expect(announcement.entries.count == RevokedAnnouncement.entryCount)
      #expect(Set(announcement.entries.map(\.hex)).isSuperset(of: announced), "\(vector.name)")
      #expect(
        announcement.entries.filter { announced.contains($0.hex) }.count == announced.count,
        "\(vector.name)")
    }
  }
}
