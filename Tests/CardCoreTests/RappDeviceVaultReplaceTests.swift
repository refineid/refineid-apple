// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  /// The confirmed record written over an unconfirmed one (RAPP v26.10.29
  /// §4.3 item 4) is stored exactly as the first write stored it.
  @Suite("Replacing a stored pairing")
  internal struct RappDeviceVaultReplaceTests {
    private static func record(role: RappEndpointRole) throws -> RappPairRecord {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      return try PairRecordFixture.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: role,
        remotePublicKey: remote.publicKey.rawRepresentation)
    }

    @Test("A replaced record reads back whole, stays active and survives the launch sweep")
    internal func replacedRecordRoundTrips() throws {
      let vault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.replace.\(UUID().uuidString)")
      defer { _ = try? vault.deleteServiceNamespace("fi.refineid.test.replace") }
      let first = try Self.record(role: .requester)
      let pairID = first.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try first.encodedBytes())

      let replacement = try Self.record(role: .requester).encodedBytes()
      try vault.replacePair(pairID: pairID, record: replacement)

      #expect(try vault.loadPair(pairID: pairID) == replacement)
      #expect(try vault.activePairIDs() == [pairID])
      #expect(try vault.pairIsRevoked(pairID: pairID) == false)
      #expect(vault.dropUnreadablePairs() == 0)
      #expect(try vault.activePairIDs() == [pairID])
      let loaded = try RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      #expect(try loaded.encodedBytes() == replacement)
    }

    @Test("A revoked or absent pairing is not replaced")
    internal func revokedPairingIsNotReplaced() throws {
      let vault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.replace.\(UUID().uuidString)")
      defer { _ = try? vault.deleteServiceNamespace("fi.refineid.test.replace") }
      let record = try Self.record(role: .proxy)
      let pairID = record.metadata().pairId
      let bytes = try record.encodedBytes()
      #expect(throws: (any Error).self) {
        try vault.replacePair(pairID: pairID, record: bytes)
      }
      try vault.insertPair(pairID: pairID, record: bytes)
      try vault.revokePair(pairID: pairID, revokedAtMilliseconds: 0)
      #expect(throws: (any Error).self) {
        try vault.replacePair(pairID: pairID, record: bytes)
      }
      #expect(try vault.loadPair(pairID: pairID) == nil)
    }
  }
#endif
