// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  /// Idle expiry over the device's vault (RAPP v26.10.29 §4.6 item 5): a
  /// pairing with no established session for 30 days is stored forgotten,
  /// and a pairing in session is recorded instead.
  @Suite("Pairing idle expiry")
  internal struct RappPairIdleExpiryTests {
    private static let namespace = "fi.refineid.test.idle-expiry"

    /// When the test pairings were made, in milliseconds since the Unix
    /// epoch.
    private static let creation: UInt64 = 1_000

    /// The smallest step of the millisecond clock.
    private static let tick: UInt64 = 1

    private static let display = "Test phone"

    /// A pairing identifier no vault in these tests holds.
    private static let absentPairID = Data(
      repeating: 1, count: RappDeviceVault.IdentifierSize.pair)

    private static func vault() -> RappDeviceVault {
      RappDeviceVault(accessGroup: nil, servicePrefix: "\(namespace).\(UUID().uuidString)")
    }

    /// A requester's pairing with a phone of its own keys, stored in
    /// `vault`.
    private static func storedPairing(in vault: RappDeviceVault) throws -> Data {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairing = try PairRecordFixture.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation,
        createdAtMilliseconds: creation)
      let pairID = pairing.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try pairing.encodedBytes())
      return pairID
    }

    private static func metadata(_ pairID: Data, in vault: RappDeviceVault) throws
      -> RappPairMetadata
    {
      try RappPairRecord.loadFromVault(pairId: pairID, vault: vault).metadata()
    }

    @Test("A pairing idle for 30 days expires silently; its name and selection go")
    internal func idlePairingExpires() throws {
      let vault = Self.vault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      let pairID = try Self.storedPairing(in: vault)
      try vault.selectPair(pairID: pairID)
      RappPairNames.remember(Self.display, pairID: pairID)
      defer { RappPairNames.forget(pairID: pairID) }
      let limit = rappPairingIdleExpiryMs()

      let early = RappPairIdleExpiry.sweep(
        in: vault, nowMilliseconds: Self.creation + limit - Self.tick, established: [])
      #expect(early == RappPairIdleExpiry.Sweep())
      #expect(RappPairIdleExpiry.holdsActivePairing(vault))

      let due = RappPairIdleExpiry.sweep(
        in: vault, nowMilliseconds: Self.creation + limit, established: [])
      #expect(due.expired == [pairID])
      #expect(due.failures == 0)
      #expect(try Self.metadata(pairID, in: vault).forgottenAtMs == Self.creation + limit)
      #expect(try vault.selectedPairID() == nil)
      #expect(RappPairNames.name(forPairID: pairID) == nil)
      #expect(!RappPairIdleExpiry.holdsActivePairing(vault))
      #expect(
        RappPairIdleExpiry.sweep(in: vault, nowMilliseconds: .max, established: []).expired
          .isEmpty, "a forgotten pairing does not expire twice")
    }

    @Test("A pairing in session is recorded, never expired, and its time renews the limit")
    internal func pairingInSessionIsRecorded() throws {
      let vault = Self.vault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      let pairID = try Self.storedPairing(in: vault)
      let limit = rappPairingIdleExpiryMs()
      let inSession = Self.creation + limit * 2

      let held = RappPairIdleExpiry.sweep(
        in: vault, nowMilliseconds: inSession, established: [pairID])
      #expect(held.expired.isEmpty)
      #expect(try Self.metadata(pairID, in: vault).lastSessionAtMs == inSession)

      let ended = inSession + limit - Self.tick
      #expect(RappPairIdleExpiry.recordSession(pairID: pairID, in: vault, nowMilliseconds: ended))
      #expect(try Self.metadata(pairID, in: vault).lastSessionAtMs == ended)
      let early = RappPairIdleExpiry.sweep(
        in: vault, nowMilliseconds: ended + limit - Self.tick, established: [])
      #expect(early.expired.isEmpty)
      let due = RappPairIdleExpiry.sweep(
        in: vault, nowMilliseconds: ended + limit, established: [])
      #expect(due.expired == [pairID])
    }

    @Test("Recording a session to a pairing the vault no longer holds changes nothing")
    internal func recordingAGonePairing() {
      let vault = Self.vault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      #expect(
        RappPairIdleExpiry.recordSession(
          pairID: Self.absentPairID, in: vault, nowMilliseconds: Self.creation))
      #expect(!RappPairIdleExpiry.holdsActivePairing(vault))
    }
  }
#endif
