// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// Forgetting a pairing and telling the peer (RAPP v26.11.2 §4.6).
@Suite("RAPP pairing revocation between the bridges")
internal struct RevocationDriveTests {
  private static let start = OperationFixture.startMilliseconds
  /// When the local user forgets the pairing, in milliseconds since the
  /// Unix epoch.
  private static let forgottenAt: UInt64 = 1_700_000_000_000
  /// Days a forgotten record keeps its key (§4.6 item 3).
  private static let noticeDays: UInt64 = 30
  private static let millisecondsPerDay: UInt64 = 86_400_000
  /// The smallest step of the millisecond clock.
  private static let tick: UInt64 = 1

  /// A confirmed pairing whose records both sit in `vault`.
  private static func storedPairing(_ vault: MemoryPairVault) throws -> PairedBridges {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    try pairing.requester.persistDeviceOnly(vault: vault)
    return pairing
  }

  @Test("A custodian that forgot the pairing sends the close in place of ready")
  internal func custodianForgets() throws {
    let vault = MemoryPairVault()
    let pairing = try PairedBridges.pair(granting: everyProfile)
    try pairing.custodian.persistDeviceOnly(vault: vault)
    #expect(
      try pairing.custodian.forget(vault: vault, forgottenAtMs: Self.forgottenAt)
        == .noticePending)
    let pairId = pairing.custodian.metadata().pairId
    let stored = try #require(vault.stored(pairId))
    #expect(try PairRecord.decode(stored).forgottenAtMilliseconds == Self.forgottenAt)
    #expect(pairing.custodian.metadata().forgottenAtMs == Self.forgottenAt)

    let (requester, custodian) = try authenticatingSessions(pairing)
    #expect(custodian.revocationNoticePending())
    #expect(!requester.revocationNoticePending())
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try custodian.sendReady(
        nonce: randomBytes(FlowLimit.readyNonce), displayName: DisplayNameFixture.custodian)
    }
    let notice = try custodian.deliverRevocationNotice()
    #expect(throws: RappBindingError.WrongPhase) { try custodian.enterEstablished() }
    let answer = try requester.receiveReady(
      bytes: notice, displayName: DisplayNameFixture.requester)
    guard case .peerClosed(.pairingRevoked, let echo?) = answer else {
      Issue.record("the requester answers the close with its echo")
      return
    }
    #expect(throws: RappBindingError.WrongPhase) { try requester.enterEstablished() }
    #expect(custodian.receiveCloseEcho(bytes: echo) == .acknowledged(.pairingRevoked))

    // Delivered, the key goes (§4.6 item 3).
    try pairing.custodian.revoke(vault: vault, revokedAtMs: Self.forgottenAt)
    #expect(vault.wasRevoked(pairId))
    #expect(vault.stored(pairId) == nil)
  }

  @Test("A requester that forgot the pairing sends the close as its first message")
  internal func requesterForgets() throws {
    let vault = MemoryPairVault()
    let pairing = try Self.storedPairing(vault)
    #expect(
      try pairing.requester.forget(vault: vault, forgottenAtMs: Self.forgottenAt)
        == .noticePending)
    let (requester, custodian) = try authenticatingSessions(pairing)
    let ready = try custodian.sendReady(
      nonce: randomBytes(FlowLimit.readyNonce), displayName: DisplayNameFixture.custodian)
    try custodian.enterEstablished()
    let operations = try RappOperationBridge.beginProxy(
      session: custodian, maximumLifetimeMs: OperationFixture.maximumLifetimeMilliseconds,
      nowMs: Self.start)
    #expect(throws: RappBindingError.WrongPhase) { try requester.enterEstablished() }
    let notice = try requester.deliverRevocationNotice()
    let answer = operations.receiveFrame(bytes: notice, nowMs: Self.start)
    #expect(answer == .echoClose(try frame(answer), reason: .pairingRevoked, endedOperation: nil))
    #expect(requester.receiveCloseEcho(bytes: ready) == .ignored, "the ready is not the echo")
    #expect(requester.receiveCloseEcho(bytes: try frame(answer)) == .acknowledged(.pairingRevoked))
  }

  @Test("A pairing forgotten during a session is revoked with the close at once")
  internal func revokedInSession() throws {
    let session = try establishedSession(
      try PairedBridges.pair(granting: everyProfile), nowMilliseconds: Self.start)
    let close = session.custodian.closeWithReason(.pairingRevoked)
    let echo = try deliver(close, to: session.requester, at: Self.start)
    #expect(echo == .echoClose(try frame(echo), reason: .pairingRevoked, endedOperation: nil))
  }

  @Test("Only a forgotten record delivers the close")
  internal func noticeNeedsAForgottenRecord() throws {
    let (requester, custodian) = try authenticatingSessions(
      try PairedBridges.pair(granting: everyProfile))
    #expect(throws: RappBindingError.WrongPhase) { _ = try custodian.deliverRevocationNotice() }
    #expect(throws: RappBindingError.WrongPhase) { _ = try requester.deliverRevocationNotice() }
  }

  @Test("An unconfirmed record is destroyed at once and nobody is told")
  internal func unconfirmedRecordIsDestroyed() throws {
    let vault = MemoryPairVault()
    let confirmed = try PairedBridges.pair(granting: everyProfile).requester.record
    let unconfirmed = RappPairRecord(
      record: try PairRecord(
        pairIdentifier: confirmed.pairIdentifier, role: confirmed.role,
        localStaticPrivate: confirmed.localStaticPrivate,
        localStaticPublic: confirmed.localStaticPublic,
        remoteStaticPublic: confirmed.remoteStaticPublic, grantsHash: confirmed.grantsHash,
        profiles: confirmed.profiles, transport: confirmed.transport,
        createdAtMilliseconds: confirmed.createdAtMilliseconds,
        peerDisplayName: confirmed.peerDisplayName, storageConfirmed: false))
    try unconfirmed.persistDeviceOnly(vault: vault)
    #expect(try unconfirmed.forget(vault: vault, forgottenAtMs: Self.forgottenAt) == .destroyed)
    #expect(vault.wasRevoked(confirmed.pairIdentifier))
    #expect(throws: RappBindingError.WrongPhase, "the key is gone here too") {
      _ = try unconfirmed.encodedBytes()
    }
  }

  @Test("A revoked record holds no key; a refused revocation keeps it for another attempt")
  internal func revocationDestroysTheKey() throws {
    let unstored = try PairedBridges.pair(granting: everyProfile).requester
    #expect(throws: RappBindingError.LocalStateFailure) {
      try unstored.revoke(vault: MemoryPairVault(), revokedAtMs: Self.forgottenAt)
    }
    _ = try unstored.encodedBytes()

    let vault = MemoryPairVault()
    let pairing = try Self.storedPairing(vault)
    let pairID = pairing.requester.metadata().pairId
    try pairing.requester.revoke(vault: vault, revokedAtMs: Self.forgottenAt)
    #expect(vault.wasRevoked(pairID))
    #expect(pairing.requester.metadata().pairId == pairID, "the description stays")
    #expect(throws: RappBindingError.WrongPhase) { _ = try pairing.requester.encodedBytes() }
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try pairing.requester.sessionPreamble(transportProfile: StreamProfile.name)
    }
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try RappSessionBridge.beginRequester(
        pair: pairing.requester, transportProfile: StreamProfile.name)
    }
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try pairing.requester.forget(vault: vault, forgottenAtMs: Self.forgottenAt)
    }
    #expect(throws: RappBindingError.WrongPhase) {
      try pairing.requester.revoke(vault: vault, revokedAtMs: Self.forgottenAt)
    }
  }

  @Test(
    "A custodian's forgotten record keeps its key for thirty days, a requester's until its idle expiry"
  )
  internal func noticeWindow() throws {
    let vault = MemoryPairVault()
    let pairing = try Self.storedPairing(vault)
    let custodianVault = MemoryPairVault()
    try pairing.custodian.persistDeviceOnly(vault: custodianVault)
    #expect(!pairing.custodian.revocationNoticeExpired(nowMs: Self.forgottenAt))
    _ = try pairing.custodian.forget(vault: custodianVault, forgottenAtMs: Self.forgottenAt)
    let window = Self.noticeDays * Self.millisecondsPerDay
    #expect(
      !pairing.custodian.revocationNoticeExpired(nowMs: Self.forgottenAt + window - Self.tick))
    #expect(pairing.custodian.revocationNoticeExpired(nowMs: Self.forgottenAt + window))
    let sessionAt = Self.forgottenAt - Self.millisecondsPerDay
    _ = try pairing.requester.sweep(vault: vault, nowMs: sessionAt, sessionEstablished: true)
    _ = try pairing.requester.forget(vault: vault, forgottenAtMs: Self.forgottenAt)
    let expiry = sessionAt + rappPairingIdleExpiryMs()
    #expect(
      !pairing.requester.revocationNoticeExpired(nowMs: Self.forgottenAt + Self.millisecondsPerDay))
    #expect(!pairing.requester.revocationNoticeExpired(nowMs: expiry - Self.tick))
    #expect(pairing.requester.revocationNoticeExpired(nowMs: expiry))
  }

  @Test("A requester's idle expiry destroys the pairing and owes nothing")
  internal func requesterExpiryDestroys() throws {
    let vault = MemoryPairVault()
    let pairing = try Self.storedPairing(vault)
    let created = pairing.requester.metadata().createdAtMs
    #expect(
      try pairing.requester.sweep(
        vault: vault, nowMs: created + rappPairingIdleExpiryMs(), sessionEstablished: false)
        == .expired)
    #expect(vault.wasRevoked(pairing.requester.metadata().pairId))
    #expect(throws: RappBindingError.WrongPhase) { _ = try pairing.requester.encodedBytes() }
  }

  @Test("The peer's new name is stored, and the same name stores nothing")
  internal func peerRenamed() throws {
    let vault = MemoryPairVault()
    let pairing = try PairedBridges.pair(granting: everyProfile)
    try pairing.custodian.persistDeviceOnly(vault: vault)
    let name = try #require(RappDisplayName("macOS - renamed-host"))
    #expect(try pairing.custodian.updatePeerDisplayName(vault: vault, name: name))
    #expect(!(try pairing.custodian.updatePeerDisplayName(vault: vault, name: name)))
    let stored = try #require(vault.stored(pairing.custodian.metadata().pairId))
    #expect(try PairRecord.decode(stored).peerDisplayName == name.text)
  }
}
