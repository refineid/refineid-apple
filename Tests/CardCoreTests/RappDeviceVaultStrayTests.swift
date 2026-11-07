// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && DEBUG
  @testable import CardCore
  import Foundation
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
  }

#endif
