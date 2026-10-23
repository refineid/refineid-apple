// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// The idle-expiry sweep behind the public interface (RAPP v26.10.22 §4.6
/// item 5): the vault stores the change first.
@Suite("RAPP pairing idle expiry through the vault")
internal struct RappPairRecordSweepTests {
  /// A vault that refuses as many writes as it was told to, then stores.
  private final class RefusingPairVault: RappPairVault, @unchecked Sendable {
    private let lock = NSLock()
    private let memory = MemoryPairVault()
    private var writesToRefuse: Int

    init(refusing writesToRefuse: Int) {
      self.writesToRefuse = writesToRefuse
    }

    func insertDeviceOnly(pairId: Data, record: Data) throws {
      try memory.insertDeviceOnly(pairId: pairId, record: record)
    }

    func replaceDeviceOnly(pairId: Data, record: Data) throws {
      let refuse = lock.withLock {
        guard writesToRefuse > 0 else { return false }
        writesToRefuse -= 1
        return true
      }
      if refuse { throw RappVaultError.Unavailable }
      try memory.replaceDeviceOnly(pairId: pairId, record: record)
    }

    func loadDeviceOnly(pairId: Data) -> Data? {
      memory.loadDeviceOnly(pairId: pairId)
    }

    func revokeDeviceOnly(pairId: Data, revokedAtMs: UInt64) throws {
      try memory.revokeDeviceOnly(pairId: pairId, revokedAtMs: revokedAtMs)
    }

    func isRevoked(pairId: Data) -> Bool {
      memory.isRevoked(pairId: pairId)
    }
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

  /// A time after the fixture's creation and short of its idle limit.
  private static func sessionTime() throws -> UInt64 {
    try created() + limit / 2
  }

  /// The fixture stored in `vault`, behind the public interface.
  private static func storedPair(in vault: RappPairVault) throws -> RappPairRecord {
    let pair = RappPairRecord(record: try makePairRecord())
    try pair.persistDeviceOnly(vault: vault)
    return pair
  }

  @Test("A held session is recorded in the vault, and the stored record expires later")
  internal func publicSweepStoresFirst() throws {
    let vault = MemoryPairVault()
    let pair = try Self.storedPair(in: vault)
    var now = try Self.created() + Self.limit * 2
    for _ in 0..<Self.heldSessionDays {
      #expect(try pair.sweep(vault: vault, nowMs: now, sessionEstablished: true) == .recorded)
      now += Self.millisecondsPerDay
    }
    let last = now - Self.millisecondsPerDay
    #expect(pair.metadata().forgottenAtMs == nil)
    #expect(pair.metadata().lastSessionAtMs == last)
    #expect(
      try pair.sweep(vault: vault, nowMs: last + Self.limit - Self.tick, sessionEstablished: false)
        == .kept)
    #expect(
      try pair.sweep(vault: vault, nowMs: last + Self.limit, sessionEstablished: false) == .expired)
    let reloaded = try RappPairRecord.loadFromVault(pairId: pair.metadata().pairId, vault: vault)
    #expect(reloaded.metadata().forgottenAtMs == last + Self.limit)
    #expect(reloaded.metadata().lastSessionAtMs == last)
  }

  @Test("A refused store changes nothing in memory, and the retry stores")
  internal func publicSweepRetries() throws {
    let expiredAt = try Self.created() + Self.limit
    let vault = RefusingPairVault(refusing: 1)
    let pair = try Self.storedPair(in: vault)
    #expect(throws: RappBindingError.LocalStateFailure) {
      try pair.sweep(vault: vault, nowMs: expiredAt, sessionEstablished: false)
    }
    #expect(pair.metadata().forgottenAtMs == nil)
    #expect(try pair.sweep(vault: vault, nowMs: expiredAt, sessionEstablished: false) == .expired)
    let reloaded = try RappPairRecord.loadFromVault(pairId: pair.metadata().pairId, vault: vault)
    #expect(reloaded.metadata().forgottenAtMs == expiredAt)
  }

  @Test("A forgotten pairing is kept; a revoked or unconfirmed one is refused")
  internal func publicSweepPhases() throws {
    let vault = MemoryPairVault()
    let pair = try Self.storedPair(in: vault)
    let forgottenAt = try Self.sessionTime()
    _ = try pair.forget(vault: vault, forgottenAtMs: forgottenAt)
    #expect(try pair.sweep(vault: vault, nowMs: .max, sessionEstablished: false) == .kept)
    #expect(pair.metadata().forgottenAtMs == forgottenAt)
    try pair.revoke(vault: vault, revokedAtMs: forgottenAt)
    #expect(throws: RappBindingError.WrongPhase) {
      try pair.sweep(vault: vault, nowMs: forgottenAt, sessionEstablished: false)
    }
    let unconfirmed = RappPairRecord(record: try makeUnconfirmedPairRecord())
    #expect(throws: RappBindingError.StorageUnconfirmed) {
      try unconfirmed.sweep(vault: vault, nowMs: forgottenAt, sessionEstablished: true)
    }
  }

  @Test("The idle expiry accessor is the engine constant")
  internal func accessorIsTheConstant() {
    #expect(rappPairingIdleExpiryMs() == PairRecord.pairingIdleExpiryMilliseconds)
    #expect(
      PairRecord.pairingIdleExpiryMilliseconds
        == PairRecord.pairingIdleExpiryDays * Self.millisecondsPerDay)
  }
}
