// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  /// Pairings stored in a format this version cannot read are removed at
  /// launch; readable ones stay.
  @Suite("Unreadable pairings")
  internal struct RappUnreadablePairsTests {
    private static let unreadableRecord = Data("not a pair record".utf8)
    private static let unreadablePairID = Data(repeating: 1, count: 16)

    @Test("An unreadable pairing goes, a readable one stays, a selection on it clears")
    internal func unreadablePairingsAreDropped() throws {
      let vault = RappDeviceVault(
        accessGroup: nil, servicePrefix: "fi.refineid.test.unreadable.\(UUID().uuidString)")
      defer { _ = try? vault.deleteServiceNamespace("fi.refineid.test.unreadable") }
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let readable = try PairRecordFixture.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation)
      let readableID = readable.metadata().pairId
      try vault.insertPair(pairID: readableID, record: try readable.encodedBytes())
      try vault.insertPair(pairID: Self.unreadablePairID, record: Self.unreadableRecord)
      try vault.selectPair(pairID: Self.unreadablePairID)

      #expect(vault.dropUnreadablePairs() == 1)
      #expect(try vault.activePairIDs() == [readableID])
      #expect(try vault.selectedPairID() == nil)
      #expect(vault.dropUnreadablePairs() == 0)
    }
  }
#endif
