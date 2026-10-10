// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import RappEngine
import XCTest

/// Proves that session discovery publishes nothing stable derived from a
/// rendezvous token, that rotating hints name only their own pairing, and
/// that a dial naming no active pairing is refused (RAPP discovery
/// hierarchy §4.1 to §4.3).
internal final class StreamSessionDiscoveryTests: XCTestCase {
  private static let tokenA = Data(repeating: 0xA1, count: 16)
  private static let tokenB = Data(repeating: 0xB2, count: 16)
  private static let unknownToken = Data(repeating: 0xC3, count: 16)
  /// A fixed instant inside one hint window.
  private static let instant = Date(timeIntervalSince1970: 1_800_000_000)
  private static let hintHexLength = 16
  private static let ephemeralNamePattern = "^refineid-[0-9a-f]{8}$"

  internal func testEphemeralNamesAreRandomAndCarryNoTokenDigest() {
    let first = StreamRendezvousName.ephemeralName()
    let second = StreamRendezvousName.ephemeralName()
    XCTAssertNotNil(first.range(of: Self.ephemeralNamePattern, options: .regularExpression))
    XCTAssertNotEqual(first, second)
    let digest = SHA256.hash(data: Self.tokenA).map { String(format: "%02x", $0) }.joined()
    XCTAssertFalse(digest.contains(first.dropFirst("refineid-".count)))
  }

  internal func testSessionRecordPublishesNoTokenMaterial() {
    let record = StreamRendezvousName.sessionRecord(
      rendezvousTokens: [Self.tokenA], at: Self.instant)
    XCTAssertEqual(record["v"], "1")
    XCTAssertEqual(record["mode"], "session")
    let tokenHex = Self.tokenA.map { String(format: "%02x", $0) }.joined()
    let digest = SHA256.hash(data: Self.tokenA).map { String(format: "%02x", $0) }.joined()
    for value in record.values {
      XCTAssertFalse(value.contains(tokenHex))
      XCTAssertFalse(digest.contains(value) && value.count >= Self.hintHexLength)
    }
    XCTAssertEqual(record[StreamRendezvousName.hintsKey]?.count, Self.hintHexLength)
  }

  internal func testHintsRotateEveryWindow() {
    let window = TimeInterval(StreamRendezvousName.hintEpochSeconds)
    let now = StreamRendezvousName.hintEpoch(at: Self.instant)
    let later = StreamRendezvousName.hintEpoch(at: Self.instant.addingTimeInterval(window))
    XCTAssertEqual(later, now + 1)
    XCTAssertNotEqual(
      StreamRendezvousName.discoveryHint(rendezvousToken: Self.tokenA, epoch: now),
      StreamRendezvousName.discoveryHint(rendezvousToken: Self.tokenA, epoch: later))
  }

  internal func testHintsNameOnlyTheirOwnPairingWithinAdjacentWindows() {
    let window = TimeInterval(StreamRendezvousName.hintEpochSeconds)
    let record = StreamRendezvousName.sessionRecord(
      rendezvousTokens: [Self.tokenA], at: Self.instant)
    XCTAssertTrue(
      StreamRendezvousName.sessionRecord(record, mayHold: Self.tokenA, at: Self.instant))
    XCTAssertTrue(
      StreamRendezvousName.sessionRecord(
        record, mayHold: Self.tokenA, at: Self.instant.addingTimeInterval(window)))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(
        record, mayHold: Self.tokenA, at: Self.instant.addingTimeInterval(2 * window)))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(record, mayHold: Self.tokenB, at: Self.instant))
  }

  internal func testAtMostFourHintsArePublished() {
    let tokens = (0..<6).map { Data(repeating: UInt8($0), count: 16) }
    let record = StreamRendezvousName.sessionRecord(rendezvousTokens: tokens, at: Self.instant)
    let hints = record[StreamRendezvousName.hintsKey]?.split(separator: ",") ?? []
    XCTAssertEqual(hints.count, StreamRendezvousName.maximumHintCount)
  }

  internal func testMinimalAndPairingRecordsAreToldApart() {
    XCTAssertTrue(
      StreamRendezvousName.sessionRecord(
        StreamRendezvousName.sessionAttributes, mayHold: Self.tokenA, at: Self.instant))
    XCTAssertFalse(
      StreamRendezvousName.sessionRecord(
        StreamRendezvousName.pairingAttributes, mayHold: Self.tokenA, at: Self.instant))
  }

  internal func testAKnownPreambleRoutesAndAnUnknownTokenIsRefused() throws {
    let candidates = [
      (pair: "a", preamble: try rappStreamSessionPreamble(rendezvousToken: Self.tokenA)),
      (pair: "b", preamble: try rappStreamSessionPreamble(rendezvousToken: Self.tokenB)),
    ]
    let known = try rappStreamSessionPreamble(rendezvousToken: Self.tokenB)
    XCTAssertEqual(
      StreamSessionRouting.route(known, among: candidates, preamble: \.preamble)?.pair, "b")
    let unknown = try rappStreamSessionPreamble(rendezvousToken: Self.unknownToken)
    XCTAssertNil(StreamSessionRouting.route(unknown, among: candidates, preamble: \.preamble))
    XCTAssertNil(
      StreamSessionRouting.route(Data("noise".utf8), among: candidates, preamble: \.preamble))
  }

  internal func testHintsReproduceTheConformanceCorpus() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Documentation/rapp-conformance/rapp-v26.10.9.json")
    let corpus = try JSONDecoder().decode(DiscoveryHintCorpus.self, from: Data(contentsOf: url))
    XCTAssertFalse(corpus.discoveryHint.isEmpty)
    for vector in corpus.discoveryHint {
      let token = try RappConformanceCorpusSupport.data(fromHex: vector.rendezvousTokenHex)
      XCTAssertEqual(
        StreamRendezvousName.discoveryHint(rendezvousToken: token, epoch: vector.epoch),
        vector.hintHex, vector.name)
    }
  }
}
