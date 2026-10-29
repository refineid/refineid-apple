// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// The phone the identity row names (RAPP v26.10.29 §4.6).
  @Suite(.serialized)
  @MainActor
  internal struct PairedPhoneTests {
    /// When the older of two pairings was made, in milliseconds since the
    /// Unix epoch.
    private static let olderCreation: UInt64 = 1_000

    /// When the newer of two pairings was made.
    private static let newerCreation: UInt64 = 2_000

    /// A requester's pairing with a phone of its own keys.
    private static func makePairing(createdAt: UInt64) throws -> RappPairRecord {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      return try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation,
        createdAtMilliseconds: createdAt)
    }

    private static func store(_ pairing: RappPairRecord, in vault: RappDeviceVault) throws {
      try vault.insertPair(pairID: pairing.metadata().pairId, record: try pairing.encodedBytes())
    }

    @Test("The paired phone is the chosen usable pairing, else the newest; a forgotten one is none")
    internal func pairedPhoneIsTheUsablePairing() throws {
      let vault = RappDeviceVault()
      let older = try Self.makePairing(createdAt: Self.olderCreation)
      let newer = try Self.makePairing(createdAt: Self.newerCreation)
      try Self.store(older, in: vault)
      try Self.store(newer, in: vault)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == newer.metadata().pairId)

      try vault.selectPair(pairID: older.metadata().pairId)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == older.metadata().pairId)

      try RappPairRevocation.forget(older, in: vault, clock: RappPlatformClock())
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == newer.metadata().pairId)

      try RappPairRevocation.forget(newer, in: vault, clock: RappPlatformClock())
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == nil)
    }

  }

#endif
