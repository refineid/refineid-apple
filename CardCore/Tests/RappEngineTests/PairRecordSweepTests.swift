// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// The idle-expiry sweep of one stored pairing (RAPP v26.10.29 §4.6 item 5).
@Suite("RAPP pairing idle expiry")
internal struct PairRecordSweepTests {
  /// Why a test store refused a write.
  private enum StoreRefusal: Error {
    case unavailable
  }

  private static let millisecondsPerDay: UInt64 = 86_400_000
  /// The smallest step of the millisecond clock.
  private static let tick: UInt64 = 1
  /// How many days past the idle limit a long-held session runs.
  private static let heldSessionDays = PairRecord.pairingIdleExpiryDays * 2
  private static let limit = PairRecord.pairingIdleExpiryMilliseconds

  /// When the fixture was created.
  private static func created() throws -> UInt64 {
    try makePairRecord().createdAtMilliseconds
  }

  /// A time after the fixture's creation and short of its idle limit, at
  /// which a session is recorded.
  private static func sessionTime() throws -> UInt64 {
    try created() + limit / 2
  }

  /// Sweeps `record` into a store that accepts every write.
  private static func swept(
    _ record: inout PairRecord, at now: UInt64, sessionEstablished: Bool
  ) throws -> PairRecordSweepOutcome {
    try record.sweep(nowMilliseconds: now, sessionEstablished: sessionEstablished) { _ in
      // The store accepts.
    }
  }

  /// The fixture with a session recorded at `time`.
  private static func recordWithSession(at time: UInt64) throws -> PairRecord {
    var record = try makePairRecord()
    #expect(try swept(&record, at: time, sessionEstablished: true) == .recorded)
    return record
  }

  @Test("A pairing without sessions expires from its creation")
  internal func expiresFromCreation() throws {
    var record = try makePairRecord()
    #expect(record.lastSessionAtMilliseconds == nil)
    let created = try Self.created()
    #expect(
      try Self.swept(&record, at: created + Self.limit - Self.tick, sessionEstablished: false)
        == .kept)
    #expect(
      try Self.swept(&record, at: created + Self.limit, sessionEstablished: false) == .expired)
    #expect(record.forgottenAtMilliseconds == created + Self.limit)
  }

  @Test("A recorded session renews the idle time")
  internal func recordedSessionRenews() throws {
    let session = try Self.sessionTime()
    var renewed = try Self.recordWithSession(at: session)
    #expect(
      try Self.swept(&renewed, at: try Self.created() + Self.limit, sessionEstablished: false)
        == .kept)
    #expect(
      try Self.swept(&renewed, at: session + Self.limit - Self.tick, sessionEstablished: false)
        == .kept)
    #expect(
      try Self.swept(&renewed, at: session + Self.limit, sessionEstablished: false) == .expired)
  }

  @Test("The recorded session time never moves back")
  internal func recordedTimeNeverMovesBack() throws {
    let session = try Self.sessionTime()
    var record = try Self.recordWithSession(at: session)
    #expect(
      try Self.swept(&record, at: session - Self.millisecondsPerDay, sessionEstablished: true)
        == .recorded)
    #expect(record.lastSessionAtMilliseconds == session)
  }

  @Test("A clock behind the last session expires nothing")
  internal func clockBehindExpiresNothing() throws {
    var record = try Self.recordWithSession(at: try Self.sessionTime())
    #expect(try Self.swept(&record, at: try Self.created(), sessionEstablished: false) == .kept)
  }

  @Test("A session held open past the idle limit never expires (INV-15)")
  internal func heldSessionNeverExpires() throws {
    var record = try makePairRecord()
    var now = try Self.created()
    for _ in 0..<Self.heldSessionDays {
      now += Self.millisecondsPerDay
      #expect(try Self.swept(&record, at: now, sessionEstablished: true) == .recorded)
    }
    #expect(record.lastSessionAtMilliseconds == now)
    #expect(
      try Self.swept(&record, at: now + Self.limit - Self.tick, sessionEstablished: false) == .kept)
    #expect(try Self.swept(&record, at: now + Self.limit, sessionEstablished: false) == .expired)
  }

  @Test("A long idle pairing with a session established is recorded, not expired")
  internal func longIdleInSessionIsRecorded() throws {
    let now = try Self.created() + Self.limit * 2
    var record = try makePairRecord()
    #expect(try Self.swept(&record, at: now, sessionEstablished: true) == .recorded)
    #expect(record.forgottenAtMilliseconds == nil)
    #expect(record.lastSessionAtMilliseconds == now)
  }

  @Test("The store receives the record the sweep leaves")
  internal func storeReceivesTheSweptRecord() throws {
    let now = try Self.created() + Self.limit
    for sessionEstablished in [true, false] {
      var record = try makePairRecord()
      let before = try record.encoded()
      var stored: Data?
      _ = try record.sweep(nowMilliseconds: now, sessionEstablished: sessionEstablished) {
        encoded in stored = encoded
      }
      let written = try #require(stored, "a change is stored")
      #expect(written != before, "the sweep changes the stored times")
      #expect(try record.encoded() == written)
    }
  }

  @Test("A sweep whose store failed is repeated whole")
  internal func failedStoreIsRepeated() throws {
    let expiredAt = try Self.created() + Self.limit
    var record = try makePairRecord()
    #expect(throws: StoreRefusal.unavailable) {
      try record.sweep(nowMilliseconds: expiredAt, sessionEstablished: false) { _ in
        throw StoreRefusal.unavailable
      }
    }
    #expect(record.forgottenAtMilliseconds == nil, "a refused store leaves the record as it was")
    var stored: Data?
    #expect(
      try record.sweep(nowMilliseconds: expiredAt, sessionEstablished: false) { stored = $0 }
        == .expired)
    let written = try PairRecord.decode(try #require(stored, "the retry stores"))
    #expect(written.forgottenAtMilliseconds == expiredAt)
    #expect(record.forgottenAtMilliseconds == expiredAt)

    let session = try Self.sessionTime()
    var unrecorded = try makePairRecord()
    #expect(throws: StoreRefusal.unavailable) {
      try unrecorded.sweep(nowMilliseconds: session, sessionEstablished: true) { _ in
        throw StoreRefusal.unavailable
      }
    }
    #expect(unrecorded.lastSessionAtMilliseconds == nil)
    #expect(try Self.swept(&unrecorded, at: session, sessionEstablished: true) == .recorded)
    #expect(unrecorded.lastSessionAtMilliseconds == session)
  }

  @Test("A sweep that changes nothing stores nothing")
  internal func unchangedStoresNothing() throws {
    var record = try makePairRecord()
    var stores = 0
    #expect(
      try record.sweep(nowMilliseconds: try Self.created(), sessionEstablished: false) { _ in
        stores += 1
      } == .kept)
    #expect(stores == 0)
  }

  @Test("A record that is not active is kept as it is")
  internal func inactiveRecordIsKept() throws {
    let forgottenAt = try Self.sessionTime()
    var forgotten = try makePairRecord().forgotten(at: forgottenAt)
    #expect(try Self.swept(&forgotten, at: .max, sessionEstablished: false) == .kept)
    #expect(forgotten.forgottenAtMilliseconds == forgottenAt)
    var unconfirmed = try makeUnconfirmedPairRecord()
    #expect(try Self.swept(&unconfirmed, at: forgottenAt, sessionEstablished: true) == .kept)
    #expect(unconfirmed.lastSessionAtMilliseconds == nil)
  }

  @Test("The last session round-trips")
  internal func lastSessionRoundTrips() throws {
    let session = try Self.sessionTime()
    let original = try Self.recordWithSession(at: session)
    let decoded = try PairRecord.decode(try original.encoded())
    #expect(decoded.lastSessionAtMilliseconds == session)
    #expect(decoded == original)
    #expect(try PairRecord.decode(try makePairRecord().encoded()).lastSessionAtMilliseconds == nil)
  }
}
