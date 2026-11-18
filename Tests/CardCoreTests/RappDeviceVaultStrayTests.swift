// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && DEBUG
  @testable import CardCore
  import CryptoKit
  import Foundation
  #if canImport(RappEngine)
    @testable import RappEngine
  #endif
  import Security
  import Testing

  /// What the vault in the shared group does about its namespace in the
  /// file keychain, and how it answers whether a pair is gone.
  @Suite("Vault items outside the shared group")
  internal struct RappDeviceVaultStrayTests {
    private static let group = "fi.refineid.test.group"
    private static let account = "stray-account"
    private static let pairID = Data(repeating: 1, count: RappDeviceVault.IdentifierSize.pair)
    private static let record = Data("pair record".utf8)
    /// The pair, selection and device-identity services planted below.
    private static let namespaceItemsPlanted = 3

    private static func makeVault(group: String? = Self.group) -> (RappDeviceVault, String) {
      let prefix = "fi.refineid.test.stray.\(UUID().uuidString)"
      return (RappDeviceVault(accessGroup: group, servicePrefix: prefix), prefix)
    }

    private static func plant(_ service: String, in vault: RappDeviceVault) {
      vault.testKeychain.fileKeychain[service, default: [:]][account] = [:]
    }

    #if canImport(RappEngine)
      private static func plantPair(
        vault: RappDeviceVault,
        createdAt: UInt64,
        forgottenAt: UInt64? = nil,
        storageConfirmed: Bool = true
      ) throws -> Data {
        let priv = Curve25519.Signing.PrivateKey()
        let remote = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        let pair: RappPairRecord
        if storageConfirmed {
          pair = try PairRecordFixture.makePairRecord(
            localStaticPrivate: priv.rawRepresentation,
            localStaticPublic: priv.publicKey.rawRepresentation,
            localRole: .proxy,
            remotePublicKey: remote,
            createdAtMilliseconds: createdAt)
        } else {
          pair = try PairRecordFixture.makeUnconfirmedPairRecord(
            localStaticPrivate: priv.rawRepresentation,
            localStaticPublic: priv.publicKey.rawRepresentation,
            localRole: .proxy,
            remotePublicKey: remote)
        }
        let plantedPairID = pair.metadata().pairId
        try pair.persistDeviceOnly(vault: vault)
        if let forgottenAt {
          _ = try pair.forget(vault: vault, forgottenAtMs: forgottenAt)
        }
        return plantedPairID
      }
    #endif

    @Test("Every item of the namespace leaves the file keychain and nothing else does")
    internal func sweepDeletesTheNamespaceOnly() throws {
      let (vault, prefix) = Self.makeVault()
      let foreign = "\(prefix)x.pair"
      Self.plant(vault.namespace.pair, in: vault)
      Self.plant(vault.namespace.selection, in: vault)
      Self.plant("\(prefix).device-identity", in: vault)
      Self.plant(foreign, in: vault)
      try vault.insertPair(pairID: Self.pairID, record: Self.record)

      #expect(try vault.deleteFileKeychainStrays() == Self.namespaceItemsPlanted)

      #expect(
        vault.testKeychain.fileKeychainCoordinates(prefix: prefix).map(\.service) == [foreign])
      #expect(try vault.loadPair(pairID: Self.pairID) == Self.record, "the vault's own pair stays")
    }

    @Test("A vault with no group lives in the file keychain and sweeps nothing")
    internal func noGroupSweepsNothing() throws {
      let (vault, _) = Self.makeVault(group: nil)
      Self.plant(vault.namespace.pair, in: vault)
      #expect(try vault.deleteFileKeychainStrays() == 0)
      #expect(!vault.testKeychain.fileKeychainCoordinates(prefix: vault.namespace.pair).isEmpty)
    }

    @Test("A refused delete is reported and the item stays for the next attempt")
    internal func refusedDeleteThrows() throws {
      let (vault, _) = Self.makeVault()
      Self.plant(vault.namespace.pair, in: vault)
      vault.testKeychain.refusal = { $0 == .delete ? errSecAuthFailed : nil }
      #expect(throws: RappDeviceVault.Failure.self) { try vault.deleteFileKeychainStrays() }
      #expect(!vault.testKeychain.fileKeychainCoordinates(prefix: vault.namespace.pair).isEmpty)

      vault.testKeychain.refusal = { _ in nil }
      #expect(try vault.deleteFileKeychainStrays() == 1)
    }

    @Test("Forgetting everything clears the file keychain too")
    internal func forgettingEverythingReachesTheFileKeychain() throws {
      let (vault, prefix) = Self.makeVault()
      Self.plant(vault.namespace.pair, in: vault)
      try vault.insertPair(pairID: Self.pairID, record: Self.record)
      _ = try vault.deleteServiceNamespace(prefix)
      #expect(vault.testKeychain.fileKeychainCoordinates(prefix: prefix).isEmpty)
      #expect(try vault.loadPair(pairID: Self.pairID) == nil)
    }

    @Test("A pair the vault holds is not gone; a removed or unknown one is")
    internal func goneFollowsTheVault() throws {
      let (vault, _) = Self.makeVault()
      #expect(try vault.pairIsGone(pairID: Self.pairID))
      try vault.insertPair(pairID: Self.pairID, record: Self.record)
      #expect(try !vault.pairIsGone(pairID: Self.pairID))
      try vault.revokePair(pairID: Self.pairID, revokedAtMilliseconds: 0)
      #expect(try vault.pairIsGone(pairID: Self.pairID))
    }

    @Test("A keychain that does not answer says nothing about a pair")
    internal func anUnreadableKeychainIsNotAnAnswer() throws {
      let (vault, _) = Self.makeVault()
      vault.testKeychain.readRefusal = errSecInteractionNotAllowed
      #expect(throws: RappDeviceVault.Failure.self) {
        _ = try vault.pairIsGone(pairID: Self.pairID)
      }
    }

    #if canImport(RappEngine)
      @Test("Sweeping the namespace with excludingRevocationNotices retains unexpired notices")
      internal func sweepingExcludingRevocationNoticesRetainsUnexpiredNotices() throws {
        let (vault, prefix) = Self.makeVault()
        let nowMs = RappPlatformClock().wallMilliseconds()
        let thirtyTwoDays = UInt64(32 * 24 * 60 * 60 * 1_000)
        let thirtyOneDays = UInt64(31 * 24 * 60 * 60 * 1_000)

        // 1. Unexpired revocation notice (forgotten 10s ago)
        let noticeID = try Self.plantPair(
          vault: vault, createdAt: nowMs - 10_000, forgottenAt: nowMs - 10_000)
        // 2. Expired notice (created 32 days ago, forgotten 31 days ago)
        let expiredID = try Self.plantPair(
          vault: vault, createdAt: nowMs - thirtyTwoDays, forgottenAt: nowMs - thirtyOneDays)
        // 3. Active pair (not forgotten)
        let activeID = try Self.plantPair(vault: vault, createdAt: nowMs - 10_000)
        // 4. Unconfirmed pair (even if marked forgotten, unconfirmed pairings are not retained)
        let unconfID = try Self.plantPair(
          vault: vault, createdAt: nowMs - 10_000, forgottenAt: nowMs - 10_000,
          storageConfirmed: false)

        // 5. Selection and non-pair service items
        try vault.selectPair(pairID: noticeID)
        Self.plant("\(prefix).credentials", in: vault)

        // Sweeping with excludingRevocationNotices: true
        let deleted = try vault.deleteServiceNamespace(prefix, excludingRevocationNotices: true)
        #expect(deleted >= 4)

        // Selection is wiped
        #expect(try vault.selectedPairID() == nil)
        // Non-pair service is wiped
        #expect(vault.testKeychain.fileKeychainCoordinates(prefix: "\(prefix).credentials").isEmpty)
        // Active pair is wiped
        #expect(try vault.loadPair(pairID: activeID) == nil)
        // Expired notice is wiped
        #expect(try vault.loadPair(pairID: expiredID) == nil)
        // Unconfirmed pair is wiped
        #expect(try vault.loadPair(pairID: unconfID) == nil)

        // Unexpired revocation notice is retained
        #expect(try vault.loadPair(pairID: noticeID) != nil)
        let loaded = try RappPairRecord.loadFromVault(pairId: noticeID, vault: vault)
        #expect(loaded.metadata().forgottenAtMs != nil)

        // Subsequent full sweep without exclusions deletes the notice as well
        _ = try vault.deleteServiceNamespace(prefix, excludingRevocationNotices: false)
        #expect(try vault.loadPair(pairID: noticeID) == nil)
      }
    #endif
  }

#endif
