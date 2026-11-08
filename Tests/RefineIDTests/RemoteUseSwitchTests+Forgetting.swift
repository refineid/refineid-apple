// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// The holder's click off forgets every pairing (RAPP v26.11.8 §4.6 item
  /// 6, CC-100), durably and before a quit lets the app go; a stop
  /// withdraws and keeps them (§4.5 item 8).
  extension RemoteUseSwitchTests {
    /// How long, in milliseconds, a destruction free to run is given to
    /// destroy what the vault holds.
    internal static let unchainedDestructionMarginMilliseconds: Int64 = 200

    /// ``unchainedDestructionMarginMilliseconds`` as a duration.
    private static let unchainedDestructionMargin = Duration.milliseconds(
      unchainedDestructionMarginMilliseconds)

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
      let pairing = try PairRecordFixture.makePairRecord(
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

    /// Destroys what a test left in `vault`, and the backlog's model of it.
    internal static func destroy(
      _ pairings: [RappPairRecord],
      in vault: RappDeviceVault,
      registry: PersistentTokenRegistry
    ) {
      for pairing in pairings {
        try? vault.revokePair(
          pairID: pairing.metadata().pairId, revokedAtMilliseconds: revocationTime)
      }
      registry.refreshPairing(in: vault)
      registry.followRevocationBacklog(in: vault)
    }

    /// Whether `vault` keeps `pairing` forgotten, in the revocation backlog.
    internal static func forgotten(_ pairing: RappPairRecord, in vault: RappDeviceVault) -> Bool {
      (try? RappPairRecord.loadFromVault(pairId: pairing.metadata().pairId, vault: vault))?
        .metadata().forgottenAtMs != nil
    }

    @Test("The holder's click off is stored first, revokes the session and forgets every pairing")
    internal func clickOffForgetsEveryPairing() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let pairing = try Self.recentPairing(in: vault)
      let other = try Self.recentPairing(in: vault)
      defer { Self.destroy([pairing, other], in: vault, registry: registry) }
      registry.refreshPairing(in: vault)
      registry.phoneThatForgot = Self.phone
      Self.holdOpenSession(over: pairing, in: registry)

      registry.forgetEveryPairing(in: vault, store: store)

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

      // No phone echoed a close, so every pairing waits forgotten in the
      // revocation backlog: it serves nothing and is followed for its phone.
      #expect(registry.forgetting == nil)
      #expect(registry.pairingDestruction == nil)
      #expect(RemoteUseForgetting.pending(in: store) == nil)
      #expect(Self.forgotten(pairing, in: vault))
      #expect(Self.forgotten(other, in: vault))
      #expect(registry.pairedPhoneID == nil)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == nil)
      let keys = Set(
        [pairing, other].map { PersistentTokenRegistry.pairingKey($0.metadata().pairId) })
      #expect(registry.revocationBacklog?.following == keys)
    }

    @Test("With no session open, the click off keeps every pairing in the revocation backlog")
    internal func clickOffWithoutSessionKeepsTheBacklog() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let pairing = try Self.recentPairing(in: vault)
      defer { Self.destroy([pairing], in: vault, registry: registry) }
      registry.refreshPairing(in: vault)

      registry.forgetEveryPairing(in: vault, store: store)
      await registry.forgetting?.value

      #expect(registry.forgetting == nil)
      #expect(registry.pairingDestruction == nil)
      #expect(RemoteUseForgetting.pending(in: store) == nil)
      #expect(Self.forgotten(pairing, in: vault))
      #expect(registry.pairedPhoneID == nil)
      #expect(
        registry.revocationBacklog?.following
          == [PersistentTokenRegistry.pairingKey(pairing.metadata().pairId)])
    }

    @Test("A quit during the click off waits until its pairings are forgotten")
    internal func quitDuringClickOffWaitsForTheForgetting() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let pairing = try Self.recentPairing(in: vault)
      defer { Self.destroy([pairing], in: vault, registry: registry) }
      Self.holdOpenSession(over: pairing, in: registry)
      let off = Self.rig().remoteUse

      registry.forgetEveryPairing(in: vault, store: store)
      let pending = try #require(
        QuitWithdrawal.begin(remoteUse: off, registry: registry),
        "remote use is off, yet the quit waits for the forgetting")
      #expect(pending.closes == nil)
      let forgetting = try #require(pending.forgetting)
      let outcome = await forgetting.value

      #expect(outcome.forgotten == [pairing.metadata().pairId])
      #expect(outcome.failures == 0)
      #expect(Self.forgotten(pairing, in: vault))
      #expect(RemoteUseForgetting.pending(in: store) == nil)
      await registry.forgetting?.value
    }

    @Test("Overlapping click offs run one forgetting at a time, and a quit waits for both")
    internal func overlappingClickOffs() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let first = try Self.recentPairing(in: vault)
      var made = [first]
      defer { Self.destroy(made, in: vault, registry: registry) }

      // The first click off waits on a session close the test holds.
      let (closeLeft, leave) = AsyncStream<Bool>.makeStream()
      let heldClose = Task<Bool, Never> {
        for await left in closeLeft {
          return left
        }
        return false
      }
      RemoteUseForgetting.request(
        at: RappPlatformClock().wallMilliseconds(), listing: vault, in: store)
      registry.finishForgetting(after: heldClose, closing: nil, in: vault, store: store)
      let firstForgetting = try #require(registry.pairingDestruction)

      // Remote use on again, a phone paired again, and turned off again
      // while the first click off still waits on its close.
      let second = try Self.recentPairing(in: vault)
      made.append(second)
      registry.forgetEveryPairing(in: vault, store: store)
      let secondForgetting = try #require(registry.pairingDestruction)
      let pending = try #require(
        QuitWithdrawal.begin(remoteUse: Self.rig().remoteUse, registry: registry))

      // A second forgetting that did not wait would have forgotten both
      // pairings by now.
      try await Task.sleep(for: Self.unchainedDestructionMargin)
      #expect(!Self.forgotten(first, in: vault), "the second waits for the first")
      #expect(!Self.forgotten(second, in: vault), "the second waits for the first")

      leave.yield(true)
      leave.finish()
      let quitWaitedFor = try #require(pending.forgetting)
      _ = await quitWaitedFor.value
      #expect(Self.forgotten(first, in: vault), "the quit let go once both were forgotten")
      #expect(Self.forgotten(second, in: vault))
      let forgottenIDs =
        (await firstForgetting.value).forgotten + (await secondForgetting.value).forgotten
      let both = Set([first.metadata().pairId, second.metadata().pairId])
      #expect(forgottenIDs.count == both.count, "each pairing is forgotten once")
      #expect(Set(forgottenIDs) == both, "the stored clicks cover both")
      await registry.forgetting?.value
      #expect(registry.forgetting == nil)
      #expect(registry.pairingDestruction == nil)
      #expect(RemoteUseForgetting.pending(in: store) == nil)
    }

    @Test("Pairing another phone keeps the replaced pairing in the backlog, apart from the new one")
    internal func replacedPairingWaitsInTheBacklog() throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let replaced = try Self.recentPairing(in: vault)
      let kept = try Self.recentPairing(in: vault)
      defer { Self.destroy([replaced, kept], in: vault, registry: registry) }

      registry.forgetReplacedPairings(keeping: kept.metadata().pairId, in: vault)
      registry.refreshPairing(in: vault)
      registry.followRevocationBacklog(in: vault)

      #expect(Self.forgotten(replaced, in: vault), "forgotten at once, so it serves nothing")
      #expect(!Self.forgotten(kept, in: vault))
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == kept.metadata().pairId)
      #expect(registry.pairedPhoneID == kept.metadata().pairId)
      #expect(
        registry.revocationBacklog?.following
          == [PersistentTokenRegistry.pairingKey(replaced.metadata().pairId)],
        "the backlog follows the replaced pairing alone")
    }

    @Test("A stop withdraws at once and keeps the pairing")
    internal func stopWithdrawsAndKeepsThePairing() throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let pairing = try Self.storedPairing(in: vault)
      let pairID = pairing.metadata().pairId
      defer {
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
