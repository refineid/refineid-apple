// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP pair record storage format")
internal struct PairRecordTests {
  /// When the fixture is forgotten, in milliseconds since the Unix epoch.
  private let forgottenAtMilliseconds: UInt64 = 1_700_000_000_000
  /// Days a forgotten record keeps its key (RAPP v26.10.29 §4.6 item 3).
  private let revocationNoticeDays: UInt64 = 30
  private let millisecondsPerDay: UInt64 = 86_400_000
  /// The smallest step of the millisecond clock.
  private let tick: UInt64 = 1

  /// A record encoded with the field named replaced by the given value, so a
  /// rejection is driven from a record that is otherwise valid.
  private func mutated(
    _ encoded: Data, _ field: String, _ value: WireValue?
  ) throws -> Data {
    guard case .map(var map) = try decodeDeterministicCbor(encoded) else {
      throw PairRecordError.invalidInput
    }
    if let value {
      map[field] = value
    } else {
      map.removeValue(forKey: field)
    }
    return try WireValue.map(map).encoded()
  }

  @Test("The record stores exactly its fields under their storage keys")
  internal func encodingMatchesTheStoredForm() throws {
    #expect(try makePairRecord().encoded() == (try expectedPairRecordValue().encoded()))
  }

  @Test("A decode round trip preserves every field")
  internal func decodeRoundTripPreservesEveryField() throws {
    let record = try makePairRecord()
    #expect(try PairRecord.decode(try record.encoded()) == record)
  }

  @Test("An unknown key is rejected")
  internal func unknownKeyIsRejected() throws {
    let encoded = try makePairRecord().encoded()
    #expect(throws: (any Error).self) {
      _ = try PairRecord.decode(try mutated(encoded, "unexpected", .unsigned(1)))
    }
  }

  @Test("A missing key is rejected")
  internal func missingKeyIsRejected() throws {
    let encoded = try makePairRecord().encoded()
    #expect(throws: (any Error).self) {
      _ = try PairRecord.decode(try mutated(encoded, "grants_hash", nil))
    }
  }

  @Test("A wrong format version is rejected")
  internal func wrongFormatVersionIsRejected() throws {
    let encoded = try makePairRecord().encoded()
    #expect(throws: (any Error).self) {
      _ = try PairRecord.decode(try mutated(encoded, "format_version", .unsigned(1)))
    }
  }

  @Test("An unregistered role is rejected")
  internal func unregisteredRoleIsRejected() throws {
    let encoded = try makePairRecord().encoded()
    #expect(throws: (any Error).self) {
      _ = try PairRecord.decode(try mutated(encoded, "role", .text("observer")))
    }
  }

  @Test("An unregistered profile is rejected")
  internal func unregisteredProfileIsRejected() throws {
    let encoded = try makePairRecord().encoded()
    #expect(throws: (any Error).self) {
      _ = try PairRecord.decode(
        try mutated(encoded, "profiles", .array([.text("fi.refineid.unknown")])))
    }
  }

  @Test("A forgotten record keeps the time it was forgotten")
  internal func forgottenRecordRoundTrips() throws {
    let forgotten = try makePairRecord().forgotten(at: forgottenAtMilliseconds)
    let decoded = try PairRecord.decode(try forgotten.encoded())
    #expect(decoded.forgottenAtMilliseconds == forgottenAtMilliseconds)
    #expect(decoded == forgotten)
  }

  @Test("A forgotten record keeps its key for thirty days")
  internal func revocationNoticeWindow() throws {
    let record = try makePairRecord()
    #expect(!record.revocationNoticeExpired(nowMilliseconds: .max))
    let forgotten = record.forgotten(at: forgottenAtMilliseconds)
    let window = revocationNoticeDays * millisecondsPerDay
    #expect(!forgotten.revocationNoticeExpired(nowMilliseconds: forgottenAtMilliseconds))
    #expect(
      !forgotten.revocationNoticeExpired(
        nowMilliseconds: forgottenAtMilliseconds + window - tick))
    #expect(
      forgotten.revocationNoticeExpired(nowMilliseconds: forgottenAtMilliseconds + window))
  }

  @Test("Only a confirmed record is stored as forgotten")
  internal func unconfirmedForgottenRecordIsRejected() throws {
    let forgotten = try makePairRecord().forgotten(at: forgottenAtMilliseconds).encoded()
    #expect(throws: (any Error).self) {
      _ = try PairRecord.decode(try mutated(forgotten, "storage_confirmed", .boolean(false)))
    }
  }

  @Test("Trailing bytes are rejected")
  internal func trailingBytesAreRejected() throws {
    let encoded = try makePairRecord().encoded()
    #expect(throws: (any Error).self) { _ = try PairRecord.decode(encoded + Data([0x00])) }
  }

  @Test("An all-zero static key is rejected")
  internal func allZeroStaticKeyIsRejected() {
    #expect(throws: (any Error).self) {
      _ = try PairRecord(
        pairIdentifier: filler(0x11, PairRecordSize.pairIdentifier),
        role: .proxy,
        localStaticPrivate: filler(0x00, PairRecordSize.staticKey),
        localStaticPublic: filler(0x44, PairRecordSize.staticKey),
        remoteStaticPublic: filler(0x55, PairRecordSize.staticKey),
        grantsHash: filler(0x66, PairRecordSize.grantsHash),
        profiles: [.cardStatus],
        transport: PairTransportBinding(profile: "p", candidateIdentifier: "c"),
        createdAtMilliseconds: 0,
        storageConfirmed: true)
    }
  }

  @Test("An empty profile set is rejected")
  internal func emptyProfileSetIsRejected() {
    #expect(throws: (any Error).self) {
      _ = try PairRecord(
        pairIdentifier: filler(0x11, PairRecordSize.pairIdentifier),
        role: .proxy,
        localStaticPrivate: filler(0x33, PairRecordSize.staticKey),
        localStaticPublic: filler(0x44, PairRecordSize.staticKey),
        remoteStaticPublic: filler(0x55, PairRecordSize.staticKey),
        grantsHash: filler(0x66, PairRecordSize.grantsHash),
        profiles: [],
        transport: PairTransportBinding(profile: "p", candidateIdentifier: "c"),
        createdAtMilliseconds: 0,
        storageConfirmed: true)
    }
  }
}
