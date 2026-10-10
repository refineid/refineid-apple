// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @Suite("RappSameAccountPairBuilderTests")
  internal struct RappSameAccountPairBuilderTests {
    @Test("Derives one pair identifier regardless of key ordering")
    internal func testSymmetricDerivation() {
      let keyA = Data(repeating: 0x11, count: 32)
      let keyB = Data(repeating: 0x22, count: 32)

      let pairIdentifierAB = RappSameAccountPairBuilder.derivePairIdentifier(
        publicKeyA: keyA,
        publicKeyB: keyB
      )
      let pairIdentifierBA = RappSameAccountPairBuilder.derivePairIdentifier(
        publicKeyA: keyB,
        publicKeyB: keyA
      )
      #expect(pairIdentifierAB == pairIdentifierBA)
      #expect(pairIdentifierAB.count == 16)
    }

    @Test("Builds valid PairRecords for requester and proxy that match each other")
    internal func testMakePairRecord() throws {
      let privPhone = Data(repeating: 0x33, count: 32)
      let keyPhone = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privPhone)
      let pubPhone = keyPhone.publicKey.rawRepresentation

      let privMac = Data(repeating: 0x44, count: 32)
      let keyMac = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privMac)
      let pubMac = keyMac.publicKey.rawRepresentation

      let macRecord = try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: privMac,
        localStaticPublic: pubMac,
        localRole: .requester,
        remotePublicKey: pubPhone,
        createdAtMilliseconds: 1_000_000
      )

      let phoneRecord = try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: privPhone,
        localStaticPublic: pubPhone,
        localRole: .proxy,
        remotePublicKey: pubMac,
        createdAtMilliseconds: 1_000_000
      )

      let macMeta = macRecord.metadata()
      let phoneMeta = phoneRecord.metadata()

      #expect(macMeta.pairId == phoneMeta.pairId)
      #expect(macMeta.role == .requester)
      #expect(phoneMeta.role == .proxy)
      #expect(macMeta.transportProfile == "stream")
      #expect(phoneMeta.transportProfile == "stream")
    }
  }
#endif
