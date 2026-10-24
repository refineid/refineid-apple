// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  /// The pairing a token configuration names is read from the vault when
  /// the request runs, so only a pairing the vault still holds is used.
  @Suite("The pairing a persistent request runs over")
  internal struct RappPersistentRequesterPairingTests {
    private static let namespace = "fi.refineid.test.persistentpairing"

    private static func makeVault() -> RappDeviceVault {
      RappDeviceVault(accessGroup: nil, servicePrefix: "\(namespace).\(UUID().uuidString)")
    }

    private static func makeRecord() throws -> RappPairRecord {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      return try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation)
    }

    @Test("The named pairing is loaded whole from the vault")
    internal func namedPairingLoads() async throws {
      let vault = Self.makeVault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      let record = try Self.makeRecord()
      let pairID = record.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try record.encodedBytes())
      let pairing = try #require(PersistentTokenPairing(pairID: pairID))
      let client = RappPersistentRequesterClient(
        displayName: "Requester", pairing: pairing, vault: vault)

      let resolved = try #require(try await client.resolvedPair())
      #expect(try resolved.encodedBytes() == record.encodedBytes())
    }

    @Test("A named pairing the vault no longer holds is not used")
    internal func removedPairingIsRefused() async throws {
      let vault = Self.makeVault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      let record = try Self.makeRecord()
      let pairID = record.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try record.encodedBytes())
      try vault.revokePair(pairID: pairID, revokedAtMilliseconds: 0)
      let pairing = try #require(PersistentTokenPairing(pairID: pairID))
      let client = RappPersistentRequesterClient(
        displayName: "Requester", pairing: pairing, vault: vault)

      await #expect(throws: RappBindingError.PairNotFound) {
        _ = try await client.resolvedPair()
      }
    }
  }
#endif
