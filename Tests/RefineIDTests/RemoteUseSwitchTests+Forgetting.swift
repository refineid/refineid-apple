// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineID

  /// The holder's click off forgets every pairing (RAPP v26.10.22 §4.6 item
  /// 6, CC-100), durably and before a quit lets the app go; a stop
  /// withdraws and keeps them (§4.5 item 8).
  extension RemoteUseSwitchTests {
    /// The defaults suite these tests keep the holder's click in.
    private static let storeName = "fi.refineid.tests.remote-use-forgetting"

    /// A defaults suite of these tests' own, emptied first.
    private static func scratchStore() -> RemoteUseForgetting.Store {
      clearScratchStore()
      return RemoteUseForgetting.Store(suiteName: storeName)
    }

    /// Removes what these tests kept.
    private static func clearScratchStore() {
      UserDefaults.standard.removePersistentDomain(forName: storeName)
    }

    /// A requester's pairing made at `createdAt`, stored in `vault`.
    private static func storedPairing(
      in vault: RappDeviceVault, createdAt: UInt64
    ) throws -> RappPairRecord {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairing = try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation,
        createdAtMilliseconds: createdAt)
      try vault.insertPair(pairID: pairing.metadata().pairId, record: try pairing.encodedBytes())
      return pairing
    }

    /// Gives `registry` a session over `pairing` as remote use had it: up
    /// over Bluetooth, the phone in sight, its card's identity offered.
    private static func holdOpenSession(
      over pairing: RappPairRecord, in registry: PersistentTokenRegistry
    ) {
      registry.holderSession = RappHeldRequesterSession(pair: pairing) { _ in
        // A session never started reports nothing worth keeping.
      }
      registry.holderSessionToken = UUID()
      registry.sessionSlot = RequesterSessionSlot()
      let dialed = registry.sessionSlot.dial(over: .bluetooth, at: .now)
      #expect(dialed)
      registry.sessionSlot.established()
      registry.holderOverBluetooth = true
      registry.holderIsAdvertising = true
      registry.certificateDER = Data("certificate".utf8)
      registry.holderLine = "TEST HOLDER"
      #expect(registry.holderSessionOpen)
    }

    @Test("The holder's click off is stored first, revokes the session and forgets every pairing")
    internal func clickOffForgetsEveryPairing() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let pairing = try Self.storedPairing(in: vault)
      let other = try Self.storedPairing(in: vault)
      let pairID = pairing.metadata().pairId
      RappPairNames.remember(Self.phone, pairID: pairID)
      defer {
        RappPairNames.forget(pairID: pairID)
        registry.refreshPairing(in: vault)
      }
      registry.refreshPairing(in: vault)
      registry.phoneThatForgot = Self.phone
      Self.holdOpenSession(over: pairing, in: registry)

      registry.forgetEveryPairing(in: vault, store: store)

      // The click is kept before anything else, and everything remote
      // stops at once.
      #expect(RemoteUseForgetting.requestedAt(in: store) != nil)
      #expect(registry.holderSession == nil)
      #expect(!registry.holderSessionOpen)
      #expect(!registry.holderInSight)
      #expect(registry.presence == nil)
      #expect(registry.certificateDER == nil)
      #expect(registry.holderLine == nil)
      #expect(registry.phoneThatForgot == nil)
      #expect(registry.pairingDestruction != nil, "the open session's close leaves first")
      let forgetting = try #require(registry.forgetting)
      await forgetting.value

      // Then every pairing is gone with its key and its name.
      #expect(registry.forgetting == nil)
      #expect(registry.pairingDestruction == nil)
      #expect(RemoteUseForgetting.requestedAt(in: store) == nil)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(try vault.loadPair(pairID: other.metadata().pairId) == nil)
      #expect(RappPairNames.name(forPairID: pairID) == nil)
      #expect(registry.pairedPhone == nil)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == nil)
    }

    @Test("With no session open, the click off destroys every pairing at once and tells nobody")
    internal func clickOffWithoutSessionOwesNothing() throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      _ = try Self.storedPairing(in: vault)
      registry.refreshPairing(in: vault)
      defer { registry.refreshPairing(in: vault) }

      registry.forgetEveryPairing(in: vault, store: store)

      #expect(registry.forgetting == nil)
      #expect(registry.pairingDestruction == nil)
      #expect(RemoteUseForgetting.requestedAt(in: store) == nil)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(registry.pairedPhone == nil)
    }

    @Test("A quit during the click off waits until its pairings are destroyed")
    internal func quitDuringClickOffWaitsForTheDestruction() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let pairing = try Self.storedPairing(in: vault)
      defer { registry.refreshPairing(in: vault) }
      Self.holdOpenSession(over: pairing, in: registry)
      let off = Self.rig().remoteUse

      registry.forgetEveryPairing(in: vault, store: store)
      let pending = try #require(
        QuitWithdrawal.begin(remoteUse: off, registry: registry),
        "remote use is off, yet the quit waits for the forgetting")
      #expect(pending.closes == nil)
      let destruction = try #require(pending.forgetting)
      let outcome = await destruction.value

      #expect(outcome.destroyed == [pairing.metadata().pairId])
      #expect(outcome.failures == 0)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(RemoteUseForgetting.requestedAt(in: store) == nil)
      await registry.forgetting?.value
    }

    @Test("A click off left unfinished is finished later; a pairing made after it stays")
    internal func unfinishedClickOffIsFinished() throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let before = try Self.storedPairing(in: vault)
      let clickedAt = before.metadata().createdAtMs + 1
      let after = try Self.storedPairing(in: vault, createdAt: clickedAt + 1)
      let beforeID = before.metadata().pairId
      RappPairNames.remember(Self.phone, pairID: beforeID)
      defer {
        RappPairNames.forget(pairID: beforeID)
        try? vault.revokePair(
          pairID: after.metadata().pairId, revokedAtMilliseconds: Self.revocationTime)
      }
      #expect(
        RemoteUseForgetting.finish(in: vault, store: store, clock: RappPlatformClock())
          == RemoteUseForgetting.Outcome(), "without a stored click nothing goes")

      RemoteUseForgetting.request(at: clickedAt, in: store)
      RemoteUseForgetting.request(at: clickedAt - 1, in: store)
      #expect(
        RemoteUseForgetting.requestedAt(in: store) == clickedAt, "a later click covers more")
      let outcome = RemoteUseForgetting.finish(in: vault, store: store, clock: RappPlatformClock())

      #expect(outcome.destroyed == [beforeID])
      #expect(outcome.failures == 0)
      #expect(try vault.activePairIDs() == [after.metadata().pairId])
      #expect(RappPairNames.name(forPairID: beforeID) == nil, "the name goes with the key")
      #expect(RemoteUseForgetting.requestedAt(in: store) == nil)
    }

    @Test("A stop withdraws at once and keeps the pairing")
    internal func stopWithdrawsAndKeepsThePairing() throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let pairing = try Self.storedPairing(in: vault)
      let pairID = pairing.metadata().pairId
      RappPairNames.remember(Self.phone, pairID: pairID)
      defer {
        RappPairNames.forget(pairID: pairID)
        try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: Self.revocationTime)
        registry.refreshPairing(in: vault)
      }
      registry.refreshPairing(in: vault)
      Self.holdOpenSession(over: pairing, in: registry)

      registry.remoteUseChanged(.stopped)

      #expect(registry.holderSession == nil)
      #expect(!registry.holderSessionOpen)
      #expect(!registry.holderInSight)
      #expect(registry.presence == nil)
      #expect(registry.redialTask == nil)
      // Withdrawn at once: no grace is left to run.
      #expect(registry.certificateDER == nil)
      #expect(registry.holderLine == nil)
      #expect(registry.offerLapseTask == nil)
      #expect(registry.forgetting == nil)
      // The pairing stays, so the next launch restores remote use on.
      #expect(registry.pairedPhone == Self.phone)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == pairID)
    }
  }

#endif
