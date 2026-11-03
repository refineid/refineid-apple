// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  /// The peer's changed name is stored in its pair record (RAPP v26.11.2
  /// §4.3 item 4); the same name stores nothing.
  @Suite(.serialized)
  internal struct RappPeerNameTests {
    private static let namespace = "fi.refineid.test.peer-name"

    private static func vault() -> RappDeviceVault {
      RappDeviceVault(accessGroup: nil, servicePrefix: "\(namespace).\(UUID().uuidString)")
    }

    /// A custodian's pairing with a computer, stored in `vault`.
    private static func storedPairing(in vault: RappDeviceVault) throws -> Data {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairing = try PairRecordFixture.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .proxy,
        remotePublicKey: remote.publicKey.rawRepresentation)
      let pairID = pairing.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try pairing.encodedBytes())
      return pairID
    }

    private static func peerName(_ pairID: Data, in vault: RappDeviceVault) throws -> String {
      try RappPairRecord.loadFromVault(pairId: pairID, vault: vault).metadata().peerDisplayName
    }

    @Test("The same name stores nothing")
    internal func sameNameStoresNothing() throws {
      let vault = Self.vault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      let pairID = try Self.storedPairing(in: vault)
      let name = try #require(RappDisplayName(PairRecordFixture.computerName))
      #expect(!RappPeerName.record(name, pairID: pairID, in: vault))
      #expect(try Self.peerName(pairID, in: vault) == PairRecordFixture.computerName)
    }

    @Test("A changed name is stored")
    internal func changedNameIsStored() throws {
      let vault = Self.vault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      let pairID = try Self.storedPairing(in: vault)
      let renamed = try #require(RappDisplayName("macOS - renamed-host"))
      #expect(RappPeerName.record(renamed, pairID: pairID, in: vault))
      #expect(try Self.peerName(pairID, in: vault) == "macOS - renamed-host")
      #expect(!RappPeerName.record(renamed, pairID: pairID, in: vault))
    }

    @Test("An unknown pairing stores nothing")
    internal func unknownPairingStoresNothing() throws {
      let vault = Self.vault()
      defer { _ = try? vault.deleteServiceNamespace(Self.namespace) }
      let absent = Data(
        repeating: 1, count: RappDeviceVault.IdentifierSize.pair)
      let name = try #require(RappDisplayName(PairRecordFixture.computerName))
      #expect(!RappPeerName.record(name, pairID: absent, in: vault))
    }
  }
#endif
