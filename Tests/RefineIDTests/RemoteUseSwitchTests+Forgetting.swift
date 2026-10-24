// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// How often a test looks again while it waits, and how many times.
  private enum Patience {
    static let pollMilliseconds: Int64 = 10
    static let poll = Duration.milliseconds(pollMilliseconds)
    static let looks = 200
  }

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

    /// Waits a while for `condition`.
    private static func wait(until condition: () -> Bool) async throws {
      for _ in 0..<Patience.looks where !condition() {
        try await Task.sleep(for: Patience.poll)
      }
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
      let directory = RecordingSameAccountDirectory(reachable: true)
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

      registry.forgetEveryPairing(in: vault, store: store, directory: directory)

      // The click is kept before anything else, and everything remote
      // stops at once.
      #expect(RemoteUseForgetting.pending(in: store) != nil)
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
      #expect(RemoteUseForgetting.pending(in: store) == nil)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(try vault.loadPair(pairID: other.metadata().pairId) == nil)
      #expect(RappPairNames.name(forPairID: pairID) == nil)
      #expect(directory.removals.count == 1, "the phones leave the account's directory")
      #expect(registry.pairedPhoneID == nil)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == nil)
    }

    @Test("A click off the directory could not take is kept, and turning on finishes it first")
    internal func unreachableDirectoryKeepsTheClick() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let directory = RecordingSameAccountDirectory(reachable: false)
      _ = try Self.storedPairing(in: vault)
      defer { registry.refreshPairing(in: vault) }

      registry.forgetEveryPairing(in: vault, store: store, directory: directory)
      await registry.forgetting?.value
      #expect(try vault.activePairIDs().isEmpty)
      #expect(
        RemoteUseForgetting.pending(in: store) != nil,
        "a same-account record that could re-pair keeps the click")

      directory.setReachable(true)
      registry.turnedOn(in: vault, store: store, directory: directory)
      await registry.forgetting?.value
      #expect(directory.removals.count == 2, "turning on tries the directory again first")
      #expect(RemoteUseForgetting.pending(in: store) == nil)
    }

    @Test("With no session open, the click off destroys every pairing at once and tells nobody")
    internal func clickOffWithoutSessionOwesNothing() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      let directory = RecordingSameAccountDirectory(reachable: true)
      defer { Self.clearScratchStore() }
      _ = try Self.storedPairing(in: vault)
      registry.refreshPairing(in: vault)
      defer { registry.refreshPairing(in: vault) }

      registry.forgetEveryPairing(in: vault, store: store, directory: directory)
      await registry.forgetting?.value

      #expect(registry.forgetting == nil)
      #expect(registry.pairingDestruction == nil)
      #expect(RemoteUseForgetting.pending(in: store) == nil)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(directory.removals.count == 1, "the phones leave the account's directory")
      #expect(registry.pairedPhoneID == nil)
    }

    @Test("A quit during the click off waits until its pairings are destroyed")
    internal func quitDuringClickOffWaitsForTheDestruction() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      let directory = RecordingSameAccountDirectory(reachable: true)
      defer { Self.clearScratchStore() }
      let pairing = try Self.storedPairing(in: vault)
      defer { registry.refreshPairing(in: vault) }
      Self.holdOpenSession(over: pairing, in: registry)
      let off = Self.rig().remoteUse

      registry.forgetEveryPairing(in: vault, store: store, directory: directory)
      let pending = try #require(
        QuitWithdrawal.begin(remoteUse: off, registry: registry),
        "remote use is off, yet the quit waits for the forgetting")
      #expect(pending.closes == nil)
      let destruction = try #require(pending.forgetting)
      let outcome = await destruction.value

      #expect(outcome.destroyed == [pairing.metadata().pairId])
      #expect(outcome.failures == 0)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(RemoteUseForgetting.pending(in: store) == nil)
      await registry.forgetting?.value
    }

    @Test("Overlapping click offs run one destruction at a time, and a quit waits for both")
    internal func overlappingClickOffs() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let directory = RecordingSameAccountDirectory(reachable: true)
      directory.hold()
      let first = try Self.storedPairing(in: vault)
      defer { registry.refreshPairing(in: vault) }

      registry.forgetEveryPairing(in: vault, store: store, directory: directory)
      let firstDestruction = try #require(registry.pairingDestruction)
      try await Self.wait { directory.waiting == 1 }

      // Remote use on again, a phone paired again, and turned off again
      // while the first click off still waits on the directory.
      let second = try Self.storedPairing(in: vault)
      registry.forgetEveryPairing(in: vault, store: store, directory: directory)
      let secondDestruction = try #require(registry.pairingDestruction)
      let pending = try #require(
        QuitWithdrawal.begin(remoteUse: Self.rig().remoteUse, registry: registry))
      #expect(directory.removals.count == 1, "the second waits for the first")

      directory.release()
      let quitWaitedFor = try #require(pending.forgetting)
      _ = await quitWaitedFor.value
      #expect(try vault.activePairIDs().isEmpty, "the quit let go once both were destroyed")
      #expect(directory.removals.count == 2)
      #expect(
        directory.removals.last == [first.metadata().pairId, second.metadata().pairId],
        "the second click covers both")
      _ = await firstDestruction.value
      _ = await secondDestruction.value
      await registry.forgetting?.value
      #expect(registry.forgetting == nil)
      #expect(registry.pairingDestruction == nil)
      #expect(RemoteUseForgetting.pending(in: store) == nil)
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
      #expect(registry.pairedPhoneID == pairID)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == pairID)
    }
  }

#endif
