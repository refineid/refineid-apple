// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineID

  /// The holder's click off is kept until its pairings and its phones'
  /// same-account records are gone (RAPP v26.10.22 §4.6 item 6, CC-100).
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
      #expect(directory.removals == 0)

      RemoteUseForgetting.request(at: clickedAt, in: store)
      RemoteUseForgetting.request(at: clickedAt - 1, in: store)
      #expect(
        RemoteUseForgetting.requestedAt(in: store) == clickedAt, "a later click covers more")
      let outcome = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)

      #expect(outcome.destroyed == [beforeID])
      #expect(outcome.failures == 0)
      #expect(try vault.activePairIDs() == [after.metadata().pairId])
      #expect(RappPairNames.name(forPairID: beforeID) == nil, "the name goes with the key")
      #expect(directory.removals == 1)
      #expect(RemoteUseForgetting.requestedAt(in: store) == nil)
    }

    @Test("A crash or an unreachable directory keeps the click until the phones leave it")
    internal func directoryIsPartOfTheClick() async throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let directory = RecordingSameAccountDirectory(reachable: false)
      _ = try Self.storedPairing(in: vault, createdAt: Self.earlierCreation)

      // The click was stored, and the app ended before anything else ran.
      RemoteUseForgetting.request(at: Self.earlierCreation + 1, in: store)

      let unreachable = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      #expect(unreachable.destroyed.count == 1)
      #expect(unreachable.failures == 1)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(RemoteUseForgetting.requestedAt(in: store) != nil, "the next try owes the directory")

      directory.setReachable(true)
      let reached = await RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock(), directory: directory)
      #expect(reached == RemoteUseForgetting.Outcome())
      #expect(directory.removals == 2)
      #expect(RemoteUseForgetting.requestedAt(in: store) == nil)
    }
  }

#endif
