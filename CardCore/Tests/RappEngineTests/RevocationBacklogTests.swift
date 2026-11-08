// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// A requester's revocation backlog between the bridges (RAPP v26.11.2 §4.6
/// item 6): a forgotten pairing waits for its custodian's echo, or for its
/// idle expiry, and serves nothing meanwhile.
@Suite("RAPP revocation backlog between the bridges")
internal struct RevocationBacklogTests {
  private static let start = OperationFixture.startMilliseconds
  /// When the pairing's last session was, in milliseconds since the Unix
  /// epoch; its user forgets it a day later.
  private static let forgottenAt: UInt64 = 1_700_000_000_000
  private static let millisecondsPerDay: UInt64 = 86_400_000
  /// The smallest step of the millisecond clock.
  private static let tick: UInt64 = 1
  /// Days the custodian stays out of reach after the requester's user
  /// forgot the pairing (§4.6 item 6).
  private static let custodianAwayDays: UInt64 = 5

  /// A stored requester pairing in `vault` whose last session was at
  /// `Self.forgottenAt` and that its user forgot a day later.
  private static func forgottenPairing(in vault: MemoryPairVault) throws -> PairedBridges {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    try pairing.requester.persistDeviceOnly(vault: vault)
    #expect(
      try pairing.requester.sweep(vault: vault, nowMs: Self.forgottenAt, sessionEstablished: true)
        == .recorded)
    #expect(
      try pairing.requester.forget(
        vault: vault, forgottenAtMs: Self.forgottenAt + millisecondsPerDay)
        == .noticePending)
    return pairing
  }

  /// The custodian of `pairing` appears: one session carries the
  /// requester's close as its first message and the custodian's echo.
  private static func custodianAppears(_ pairing: PairedBridges) throws -> RappCloseEcho {
    let (requester, custodian) = try authenticatingSessions(pairing)
    let ready = try custodian.sendReady(
      nonce: randomBytes(FlowLimit.readyNonce), displayName: DisplayNameFixture.custodian)
    try custodian.enterEstablished()
    let operations = try RappOperationBridge.beginProxy(
      session: custodian, maximumLifetimeMs: OperationFixture.maximumLifetimeMilliseconds,
      nowMs: start)
    let notice = try requester.deliverRevocationNotice()
    let answer = operations.receiveFrame(bytes: notice, nowMs: start)
    #expect(requester.receiveCloseEcho(bytes: ready) == .ignored)
    return requester.receiveCloseEcho(bytes: try frame(answer))
  }

  @Test("A forgotten pairing whose custodian appears five days later is destroyed on the echo")
  internal func backlogDeliveredDaysLater() throws {
    let vault = MemoryPairVault()
    let pairing = try Self.forgottenPairing(in: vault)
    let appearedAt = Self.forgottenAt + (1 + Self.custodianAwayDays) * Self.millisecondsPerDay
    #expect(!pairing.requester.revocationNoticeExpired(nowMs: appearedAt))
    #expect(
      try pairing.requester.sweep(vault: vault, nowMs: appearedAt, sessionEstablished: false)
        == .kept)
    #expect(try Self.custodianAppears(pairing) == .acknowledged(.pairingRevoked))
    try pairing.requester.revoke(vault: vault, revokedAtMs: appearedAt)
    let pairId = pairing.requester.metadata().pairId
    #expect(vault.wasRevoked(pairId))
    #expect(vault.stored(pairId) == nil)
  }

  @Test("A forgotten pairing whose custodian never appears goes 30 days after its last session")
  internal func backlogExpiresWithTheLastSession() throws {
    let vault = MemoryPairVault()
    let pairing = try Self.forgottenPairing(in: vault)
    let pairId = pairing.requester.metadata().pairId
    let expiry = Self.forgottenAt + rappPairingIdleExpiryMs()
    #expect(
      try pairing.requester.sweep(
        vault: vault, nowMs: expiry - Self.tick, sessionEstablished: false)
        == .kept)
    #expect(vault.stored(pairId) != nil, "the forgotten pairing still waits for its custodian")
    #expect(pairing.requester.revocationNoticeExpired(nowMs: expiry))
    _ = try pairing.requester.sweep(vault: vault, nowMs: expiry, sessionEstablished: false)
    #expect(vault.wasRevoked(pairId))
    #expect(vault.stored(pairId) == nil)
  }

  @Test("A forgotten requester record never serves a session")
  internal func forgottenRecordServesNothing() throws {
    let pairing = try Self.forgottenPairing(in: MemoryPairVault())
    let (requester, custodian) = try authenticatingSessions(pairing)
    let ready = try custodian.sendReady(
      nonce: randomBytes(FlowLimit.readyNonce), displayName: DisplayNameFixture.custodian)
    #expect(throws: RappBindingError.WrongPhase, "no session.hello leaves a forgotten record") {
      _ = try requester.receiveReady(bytes: ready, displayName: DisplayNameFixture.requester)
    }
    #expect(throws: RappBindingError.WrongPhase, "no identity and no operation without a session") {
      try requester.enterEstablished()
    }
  }

  @Test("Two forgotten pairings pending at once both resolve")
  internal func twoForgottenPairingsResolve() throws {
    let vault = MemoryPairVault()
    let first = try Self.forgottenPairing(in: vault)
    let second = try Self.forgottenPairing(in: vault)
    let appearedAt = Self.forgottenAt + (1 + Self.custodianAwayDays) * Self.millisecondsPerDay
    #expect(try Self.custodianAppears(second) == .acknowledged(.pairingRevoked))
    try second.requester.revoke(vault: vault, revokedAtMs: appearedAt)
    #expect(vault.stored(first.requester.metadata().pairId) != nil, "the other one still waits")
    #expect(try Self.custodianAppears(first) == .acknowledged(.pairingRevoked))
    try first.requester.revoke(vault: vault, revokedAtMs: appearedAt)
    for pairing in [first, second] {
      #expect(vault.wasRevoked(pairing.requester.metadata().pairId))
    }
  }
}
