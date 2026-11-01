// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineID

  /// What the published identity's token configuration carries: the
  /// pairing's identifier, never its keys.
  @Suite(.serialized)
  @MainActor
  internal struct PersistentTokenPairingTests {
    /// When the pairing was made, in milliseconds since the Unix epoch.
    private static let creation: UInt64 = 1_000

    /// A requester's pairing between `local` and a phone holding `remote`.
    private static func makePairing(
      local: Curve25519.KeyAgreement.PrivateKey,
      remote: Curve25519.KeyAgreement.PrivateKey
    ) throws -> RappPairRecord {
      try PairRecordFixture.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation,
        createdAtMilliseconds: creation)
    }

    @Test("The token configuration names the pairing and holds none of its keys")
    internal func configurationHoldsOnlyThePairIdentifier() throws {
      let vault = RappDeviceVault()
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairing = try Self.makePairing(local: local, remote: remote)
      let pairID = pairing.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try pairing.encodedBytes())

      let published = try #require(PersistentTokenRegistry.publishedPairing(in: vault))
      let data = published.configurationData
      #expect(data == pairID)
      #expect(!data.contains(local.rawRepresentation))
      #expect(!data.contains(local.publicKey.rawRepresentation))
      #expect(!data.contains(remote.publicKey.rawRepresentation))
      #expect(PersistentTokenPairing(configurationData: data) == published)
    }

    @Test("An encoded pair record is not token configuration data")
    internal func encodedRecordIsRefused() throws {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairing = try Self.makePairing(local: local, remote: remote)
      #expect(PersistentTokenPairing(configurationData: try pairing.encodedBytes()) == nil)
      #expect(PersistentTokenPairing(configurationData: nil) == nil)
    }

    @Test("A pairing whose record does not load is not published")
    internal func unreadablePairingIsNotPublished() throws {
      let vault = RappDeviceVault()
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairID = try Self.makePairing(local: local, remote: remote).metadata().pairId
      try vault.insertPair(pairID: pairID, record: Data(remote.publicKey.rawRepresentation))
      #expect(try vault.activePairIDs() == [pairID])
      #expect(PersistentTokenRegistry.publishedPairing(in: vault) == nil)
    }

    @Test("No pairing in the vault publishes no pairing")
    internal func emptyVaultPublishesNothing() {
      #expect(PersistentTokenRegistry.publishedPairing(in: RappDeviceVault()) == nil)
    }
  }
#endif
