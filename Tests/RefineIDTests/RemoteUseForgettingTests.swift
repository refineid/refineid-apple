// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// The holder's click off is kept until its pairings and its phones'
  /// same-account records are gone (RAPP v26.10.29 §4.6 item 6, CC-100).
  @Suite(.serialized)
  internal struct RemoteUseForgettingTests {
    /// The defaults suite these tests keep the holder's click in.
    private static let storeName = "fi.refineid.tests.remote-use-forgetting.finish"

    private static let phone = "Alpha iPhone"

    /// When the earlier test pairing was made, in milliseconds since the
    /// Unix epoch.
    private static let earlierCreation: UInt64 = 1_000

    /// When a test pairing is revoked; the vault records no time for it.
    private static let revocationTime: UInt64 = 0

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

    @Test("A click off left unfinished is finished later; a pairing made after it stays")
    internal func unfinishedClickOffIsFinished() async throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let directory = RecordingSameAccountDirectory(reachable: true)
      let before = try Self.storedPairing(in: vault, createdAt: Self.earlierCreation)
      let clickedAt = Self.earlierCreation + 1
      let after = try Self.storedPairing(in: vault, createdAt: clickedAt + 1)
      let beforeID = before.metadata().pairId
      RappPairNames.remember(Self.phone, pairID: beforeID)
      defer {
        RappPairNames.forget(pairID: beforeID)
        try? vault.revokePair(
          pairID: after.metadata().pairId, revokedAtMilliseconds: Self.revocationTime)
      }
      let idle = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      #expect(idle == RemoteUseForgetting.Outcome(), "without a stored click nothing goes")
      #expect(directory.removals.isEmpty)

      // The click was stored with the pairings it forgets, and the app
      // ended before anything else ran.
      RemoteUseForgetting.request(
        at: clickedAt, forgetting: [beforeID], listed: true, in: store)
      let outcome = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)

      #expect(outcome.destroyed == [beforeID])
      #expect(outcome.failures == 0)
      #expect(try vault.activePairIDs() == [after.metadata().pairId])
      #expect(RappPairNames.name(forPairID: beforeID) == nil, "the name goes with the key")
      #expect(directory.removals == [[beforeID]], "only its own phones leave the directory")
      #expect(RemoteUseForgetting.pending(in: store) == nil)
    }

    @Test("A later click covers an earlier one still pending")
    internal func laterClickCovers() {
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let first = Data("first pairing id".utf8)
      let second = Data("second pairing id".utf8)
      RemoteUseForgetting.request(
        at: Self.earlierCreation + 1, forgetting: [first], listed: true, in: store)
      RemoteUseForgetting.request(
        at: Self.earlierCreation, forgetting: [second], listed: true, in: store)
      let pending = RemoteUseForgetting.pending(in: store)
      #expect(pending?.clickedAtMs == Self.earlierCreation + 1)
      #expect(Set(pending?.pairIDs ?? []) == [first, second])
      #expect(pending?.needsListing == false)
    }

    @Test("A click stored while the vault could not be listed lists it before destroying")
    internal func unlistedClickIsListedFirst() async throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let directory = RecordingSameAccountDirectory(reachable: true)
      let before = try Self.storedPairing(in: vault, createdAt: Self.earlierCreation)
      let clickedAt = Self.earlierCreation + 1
      let after = try Self.storedPairing(in: vault, createdAt: clickedAt + 1)
      defer {
        try? vault.revokePair(
          pairID: after.metadata().pairId, revokedAtMilliseconds: Self.revocationTime)
      }
      RemoteUseForgetting.request(at: clickedAt, forgetting: [], listed: false, in: store)
      #expect(RemoteUseForgetting.pending(in: store)?.needsListing == true)

      let outcome = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      #expect(outcome.destroyed == [before.metadata().pairId])
      #expect(directory.removals == [[before.metadata().pairId]])
      #expect(try vault.activePairIDs() == [after.metadata().pairId])
      #expect(RemoteUseForgetting.pending(in: store) == nil)
    }

    @Test("A crash or a directory still holding the phones keeps the click until they leave")
    internal func directoryIsPartOfTheClick() async throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let directory = RecordingSameAccountDirectory(reachable: false)
      let pairing = try Self.storedPairing(in: vault, createdAt: Self.earlierCreation)
      let pairID = pairing.metadata().pairId

      // The click was stored, and the app ended before anything else ran.
      RemoteUseForgetting.request(
        at: Self.earlierCreation + 1, forgetting: [pairID], listed: true, in: store)

      let held = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      #expect(held.destroyed == [pairID])
      #expect(held.failures == 1)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(RemoteUseForgetting.pending(in: store) != nil, "the next try owes the directory")

      directory.setReachable(true)
      let reached = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      #expect(reached == RemoteUseForgetting.Outcome(), "nothing left to destroy")
      #expect(directory.removals == [[pairID], [pairID]], "the directory is asked again")
      #expect(RemoteUseForgetting.pending(in: store) == nil)
    }

    @Test("An attempt clears only the click it finished, never one stored meanwhile")
    internal func compareAndClear() async throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let directory = RecordingSameAccountDirectory(reachable: true)
      let first = try Self.storedPairing(in: vault, createdAt: Self.earlierCreation)
      let second = try Self.storedPairing(in: vault, createdAt: Self.earlierCreation + 1)
      let firstID = first.metadata().pairId
      let secondID = second.metadata().pairId
      RemoteUseForgetting.request(
        at: Self.earlierCreation + 1, forgetting: [firstID], listed: true, in: store)
      directory.onRemoval {
        // A second click off arrives while the first is being finished.
        RemoteUseForgetting.request(
          at: Self.earlierCreation + 2, forgetting: [secondID], listed: true, in: store)
      }

      _ = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      let later = try #require(RemoteUseForgetting.pending(in: store), "the second click stays")
      #expect(Set(later.pairIDs) == [firstID, secondID])

      _ = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      #expect(RemoteUseForgetting.pending(in: store) == nil)
      #expect(try vault.activePairIDs().isEmpty)
    }
  }

#endif
