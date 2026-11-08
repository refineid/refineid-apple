// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && DEBUG
  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// A failed session's error names the paired device it belonged to.
  @Suite(.serialized)
  internal struct DevErrorLogPeerTests {
    /// When the stored pairing is revoked after the test.
    private static let revocationTime: UInt64 = 1

    @Test
    internal func aStoredPairingIsNamedByItsPeer() throws {
      let vault = RappDeviceVault()
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairing = try PairRecordFixture.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation)
      let pairID = pairing.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try pairing.encodedBytes())
      defer { try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: Self.revocationTime) }

      #expect(DevErrorLog.peerName(pairID: pairID, vault: vault) == PairRecordFixture.phoneName)
    }

    @Test
    internal func anUnknownPairingSaysSo() {
      let vault = RappDeviceVault()
      let unknown = Data(repeating: 0xEE, count: 16)
      #expect(DevErrorLog.peerName(pairID: unknown, vault: vault) == "unknown pairing")
      #expect(DevErrorLog.peerName(pairID: nil, vault: vault) == "unknown pairing")
    }
  }
#endif
