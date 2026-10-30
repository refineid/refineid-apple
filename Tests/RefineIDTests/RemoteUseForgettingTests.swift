// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// The holder's click off is kept until its pairings are gone (RAPP
  /// v26.10.29 §4.6 item 6, CC-100).
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
      let pairing = try PairRecordFixture.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation,
        createdAtMilliseconds: createdAt)
      try vault.insertPair(pairID: pairing.metadata().pairId, record: try pairing.encodedBytes())
      return pairing
    }

    @Test("A click off left unfinished is finished later; a pairing made after it stays")
    internal func unfinishedClickOffIsFinished() throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
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
      let idle = RemoteUseForgetting.finish(in: vault, store: store, clock: RappPlatformClock())
      #expect(idle == RemoteUseForgetting.Outcome(), "without a stored click nothing goes")

      // The click was stored with the pairings it forgets, and the app
      // ended before anything else ran.
      RemoteUseForgetting.request(
        at: clickedAt, forgetting: [beforeID], listed: true, in: store)
      let outcome = RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock())

      #expect(outcome.destroyed == [beforeID])
      #expect(outcome.failures == 0)
      #expect(try vault.activePairIDs() == [after.metadata().pairId])
      #expect(RappPairNames.name(forPairID: beforeID) == nil, "the name goes with the key")
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
    internal func unlistedClickIsListedFirst() throws {
      let vault = RappDeviceVault()
      let store = Self.scratchStore()
      defer { Self.clearScratchStore() }
      let before = try Self.storedPairing(in: vault, createdAt: Self.earlierCreation)
      let clickedAt = Self.earlierCreation + 1
      let after = try Self.storedPairing(in: vault, createdAt: clickedAt + 1)
      defer {
        try? vault.revokePair(
          pairID: after.metadata().pairId, revokedAtMilliseconds: Self.revocationTime)
      }
      RemoteUseForgetting.request(at: clickedAt, forgetting: [], listed: false, in: store)
      #expect(RemoteUseForgetting.pending(in: store)?.needsListing == true)

      let outcome = RemoteUseForgetting.finish(
        in: vault, store: store, clock: RappPlatformClock())
      #expect(outcome.destroyed == [before.metadata().pairId])
      #expect(try vault.activePairIDs() == [after.metadata().pairId])
      #expect(RemoteUseForgetting.pending(in: store) == nil)
    }
  }

#endif
