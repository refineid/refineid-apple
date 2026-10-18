// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

/// Replays the routing and withdrawal corpora byte for byte.
@Suite("RAPP v26.10.18 routing and withdrawal corpora")
internal struct AnnouncementCorpusTests {
  private static let accepted = "accepted"

  private static func publicKey(_ privateHex: String) throws -> Data {
    try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: privateHex))
      .publicKey.rawRepresentation
  }

  /// The custodian's key for `pairID` under `info`.
  private static func custodianKey(
    _ keys: PairKeysVector, pairID: Data, info: Data
  ) throws -> SymmetricKey {
    try #require(
      PairKeys.derive(
        pairIdentifier: pairID,
        localStaticPrivate: Data(hex: keys.custodianStaticPrivateHex),
        remoteStaticPublic: publicKey(keys.requesterStaticPrivateHex),
        info: info))
  }

  private static func hex(_ key: SymmetricKey) -> String {
    key.withUnsafeBytes { Data($0) }.hex
  }

  /// The custodian's withdrawal key from the corpus's synthetic pairing.
  private static func withdrawalKey(_ corpus: WithdrawalCorpus) throws -> WithdrawalKey {
    let keys = try #require(corpus.withdrawalKey.first)
    #expect(try publicKey(keys.custodianStaticPrivateHex).hex == keys.custodianStaticPublicHex)
    let derived = try #require(
      PairKeys.derive(
        pairIdentifier: try Data(hex: keys.pairIDHex),
        localStaticPrivate: Data(hex: keys.custodianStaticPrivateHex),
        remoteStaticPublic: Data(hex: keys.requesterStaticPublicHex),
        info: PairKeys.withdrawalInfo))
    #expect(hex(derived) == keys.withdrawalKeyHex)
    return WithdrawalKey(key: derived)
  }

  @Test("Both endpoints derive the vector's keys from the static agreement")
  internal func pairKeys() throws {
    let corpus = try CorpusFile.routing(filePath: #filePath)
    #expect(corpus.protocolDocumentVersion == "26.10.18")
    for vector in corpus.pairKeys {
      let pairID = try Data(hex: vector.pairIDHex)
      for (info, expected) in [
        (PairKeys.discoveryInfo, vector.discoveryKeyHex),
        (PairKeys.routingInfo, vector.routingKeyHex),
      ] {
        #expect(Self.hex(try Self.custodianKey(vector, pairID: pairID, info: info)) == expected)
        let requester = try #require(
          PairKeys.derive(
            pairIdentifier: pairID,
            localStaticPrivate: Data(hex: vector.requesterStaticPrivateHex),
            remoteStaticPublic: Self.publicKey(vector.custodianStaticPrivateHex),
            info: info))
        #expect(Self.hex(requester) == expected, "\(vector.name)")
      }
    }
  }

  @Test("Discovery hints and their epoch window match")
  internal func discoveryHints() throws {
    let corpus = try CorpusFile.routing(filePath: #filePath)
    let keys = try #require(corpus.pairKeys.first)
    let key = DiscoveryKey(
      key: try Self.custodianKey(
        keys, pairID: try Data(hex: keys.pairIDHex), info: PairKeys.discoveryInfo))
    for vector in corpus.discoveryHint {
      #expect(DiscoveryRecord.epoch(unixTimeSeconds: vector.unixTimeSeconds) == vector.epoch)
      #expect(key.hint(epoch: vector.epoch).hex == vector.discoveryHintHex, "\(vector.name)")
    }
    for vector in corpus.discoveryAcceptance {
      let record = DiscoveryRecord(hints: [try Data(hex: vector.publishedHintHex)], revoked: nil)
      #expect(
        key.matches(record, epoch: vector.requesterEpoch) == (vector.expected == Self.accepted),
        "\(vector.name)")
    }
  }

  @Test("Routing tags, preambles and custodian lookup match")
  internal func routing() throws {
    let corpus = try CorpusFile.routing(filePath: #filePath)
    let keys = try #require(corpus.pairKeys.first)
    let key = RoutingKey(
      key: try Self.custodianKey(
        keys, pairID: try Data(hex: keys.pairIDHex), info: PairKeys.routingInfo))
    for vector in corpus.routingTag {
      let tag = key.tag(profile: vector.transportProfile, nonce: try Data(hex: vector.nonceHex))
      #expect(tag?.hex == vector.routingTagHex, "\(vector.name)")
    }
    for vector in corpus.routingPreamble {
      let preamble: RoutingPreamble =
        if let nonce = vector.nonceHex, let tag = vector.routingTagHex {
          .session(SessionRouting(nonce: try Data(hex: nonce), tag: try Data(hex: tag)))
        } else {
          .pairing
        }
      #expect(
        try preamble.encoded(profile: vector.transportProfile).hex == vector.encodedHex,
        "\(vector.name)")
      #expect(
        try RoutingPreamble.decode(
          try Data(hex: vector.encodedHex), profile: vector.transportProfile) == preamble)
    }
    for vector in corpus.routingLookup {
      let routing = try #require(SessionRouting(try Data(hex: vector.routingHex)))
      let candidates = try vector.custodianPairIDsHex.map { pairID in
        RoutingKey(
          key: try Self.custodianKey(
            keys, pairID: try Data(hex: pairID), info: PairKeys.routingInfo))
      }
      #expect(
        RoutingKey.route(keys: candidates, profile: vector.transportProfile, routing: routing)
          == vector.expectedIndex, "\(vector.name)")
    }
  }

  @Test("Session records parse as the corpus says and select the most recently used")
  internal func discoveryRecords() throws {
    let corpus = try CorpusFile.routing(filePath: #filePath)
    for vector in corpus.discoveryRecord {
      let parsed = DiscoveryRecord.parse(vector.entries)
      #expect((parsed != nil) == (vector.expected == Self.accepted), "\(vector.name)")
      if let parsed {
        #expect(parsed.hints.map(\.hex) == vector.hintsHex, "\(vector.name)")
      }
    }
    for vector in corpus.announcementSelection {
      let candidates = try vector.candidates.map { candidate in
        AnnouncementCandidate(
          hint: try Data(hex: candidate.hintHex), lastUsedMilliseconds: candidate.lastUsedMs)
      }
      #expect(
        DiscoveryRecord.assemble(candidates, revoked: nil).hints.map(\.hex)
          == vector.announcedHex,
        "\(vector.name)")
    }
  }

  @Test("Withdrawal keys, hints and their minute window match")
  internal func withdrawalHints() throws {
    let corpus = try CorpusFile.withdrawal(filePath: #filePath)
    #expect(corpus.protocolDocumentVersion == "26.10.18")
    let keys = try #require(corpus.withdrawalKey.first)
    let key = try Self.withdrawalKey(corpus)
    for vector in corpus.withdrawalHint {
      let instance = try #require(InstanceName(vector.instanceName))
      #expect(WithdrawnRecord.counter(unixTimeSeconds: vector.unixTimeSeconds) == vector.counter)
      #expect(
        key.hint(instance: instance, counter: vector.counter).hex == vector.withdrawalHintHex,
        "\(vector.name)")
    }
    for vector in corpus.withdrawalAcceptance {
      let published = key.hint(
        instance: try #require(InstanceName(vector.publishedInstance)),
        counter: vector.publishedCounter)
      let record = WithdrawnRecord(
        entries: [published] + Array(repeating: Data(count: AnnouncementText.hintSize), count: 7))
      let requester = WithdrawalKey(
        key: try #require(
          PairKeys.derive(
            pairIdentifier: try Data(hex: vector.requesterPairIDHex),
            localStaticPrivate: Data(hex: keys.requesterStaticPrivateHex),
            remoteStaticPublic: Data(hex: keys.custodianStaticPublicHex),
            info: PairKeys.withdrawalInfo)))
      let matched = requester.matches(
        record, instance: try #require(InstanceName(vector.requesterInstance)),
        counter: vector.requesterCounter)
      #expect(matched == (vector.expected == Self.accepted), "\(vector.name)")
    }
  }

  @Test("Withdrawn records, selection and the close body match")
  internal func withdrawnRecords() throws {
    let corpus = try CorpusFile.withdrawal(filePath: #filePath)
    let key = try Self.withdrawalKey(corpus)
    for vector in corpus.withdrawnRecord {
      let parsed = try #require(WithdrawnRecord.parse(vector.entries), "\(vector.name)")
      let matched = key.matches(
        parsed, instance: try #require(InstanceName(vector.instanceName)),
        counter: vector.requesterCounter)
      #expect(matched == (vector.expected == Self.accepted), "\(vector.name)")
    }
    for vector in corpus.malformedRecord {
      #expect(WithdrawnRecord.parse(vector.entries) == nil, "\(vector.name)")
    }
    for vector in corpus.announcementSelection {
      let candidates = try vector.candidates.map { candidate in
        AnnouncementCandidate(
          hint: try Data(hex: candidate.hintHex), lastUsedMilliseconds: candidate.lastUsedMs)
      }
      let record = try #require(
        WithdrawnRecord.assemble(candidates) { Data(repeating: 0, count: $0) })
      #expect(
        Set(vector.announcedHex).isSubset(of: Set(record.entries.map(\.hex))), "\(vector.name)")
    }
    for vector in corpus.sessionClose {
      let body = WireValue.map([
        "reason": .text(vector.reason),
        "last_received_sequence": .unsigned(vector.lastReceivedSequence),
      ])
      #expect(try body.encoded().hex == vector.bodyCborHex, "\(vector.name)")
      #expect(RappCloseReason(rawValue: vector.reason) != nil)
    }
  }

  @Test("A replayed routing nonce is refused")
  internal func replayIsRefused() {
    var cache = RoutingReplayCache()
    let nonce = Data(repeating: 1, count: SessionRouting.nonceSize)
    let first = cache.admit(nonce)
    let second = cache.admit(nonce)
    #expect(first)
    #expect(!second)
  }

  @Test("An instance name must be the instance portion only")
  internal func instanceNameRules() {
    #expect(InstanceName("refineid-7f2a1c84") != nil)
    #expect(InstanceName("refineid.v2") != nil)
    #expect(InstanceName("") == nil)
    #expect(InstanceName(String(repeating: "a", count: InstanceName.maximumSize + 1)) == nil)
    #expect(InstanceName("refineid-7f2a1c84.local") == nil)
    #expect(InstanceName("refineid._refineid-stream._tcp") == nil)
  }
}
