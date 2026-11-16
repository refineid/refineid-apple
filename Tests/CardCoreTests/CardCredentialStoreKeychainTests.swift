// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0
// (https://www.apache.org/licenses/LICENSE-2.0).

import Foundation
import Security
import Testing

@testable import CardCore

/// Unshared and shared keychain CRUD entry points on ``CardCredentialStore``.
@Suite(.serialized)
internal struct CardCredentialStoreKeychainTests {
  private static let firstValue = "synthetic-first"
  private static let secondValue = "synthetic-second"
  private static let emptyMarker = ""
  private static let namespacePrefix = "fi.refineid."
  private static let sampleGroupPrefix = "SYNTHETIC."

  private static func uniqueAccount(_ label: String) -> String {
    "fi.refineid.test.\(label).\(UUID().uuidString)"
  }

  @Test("Unshared CRUD stores, replaces, checks, reads, and deletes an account")
  internal func unsharedCrudRoundTrip() {
    #expect(TestCredentialEnvironment.isTestMode)
    let account = Self.uniqueAccount("unshared")
    defer { CardCredentialStore.delete(account: account) }

    #expect(!CardCredentialStore.exists(account: account))
    #expect(CardCredentialStore.read(account: account) == nil)

    #expect(CardCredentialStore.write(Self.firstValue, account: account) == errSecSuccess)
    #expect(CardCredentialStore.exists(account: account))
    #expect(CardCredentialStore.read(account: account) == Self.firstValue)

    #expect(CardCredentialStore.write(Self.secondValue, account: account) == errSecSuccess)
    #expect(CardCredentialStore.exists(account: account))
    #expect(CardCredentialStore.read(account: account) == Self.secondValue)

    CardCredentialStore.delete(account: account)
    #expect(!CardCredentialStore.exists(account: account))
    #expect(CardCredentialStore.read(account: account) == nil)

    CardCredentialStore.delete(account: account)
    #expect(!CardCredentialStore.exists(account: account))
  }

  @Test("Shared CRUD stores, replaces, checks, reads, and deletes an account")
  internal func sharedCrudRoundTrip() {
    #expect(TestCredentialEnvironment.isTestMode)
    let account = Self.uniqueAccount("shared")
    defer { CardCredentialStore.deleteShared(account: account) }

    #expect(!CardCredentialStore.existsShared(account: account))
    #expect(CardCredentialStore.readShared(account: account) == nil)

    #expect(CardCredentialStore.writeShared(Self.firstValue, account: account) == errSecSuccess)
    #expect(CardCredentialStore.existsShared(account: account))
    #expect(CardCredentialStore.readShared(account: account) == Self.firstValue)

    #expect(CardCredentialStore.writeShared(Self.secondValue, account: account) == errSecSuccess)
    #expect(CardCredentialStore.existsShared(account: account))
    #expect(CardCredentialStore.readShared(account: account) == Self.secondValue)

    CardCredentialStore.deleteShared(account: account)
    #expect(!CardCredentialStore.existsShared(account: account))
    #expect(CardCredentialStore.readShared(account: account) == nil)

    CardCredentialStore.deleteShared(account: account)
    #expect(!CardCredentialStore.existsShared(account: account))
  }

  @Test("Shared CRUD stores and clears an empty refusal-style marker")
  internal func sharedEmptyMarkerRoundTrip() throws {
    #expect(TestCredentialEnvironment.isTestMode)
    let account = Self.uniqueAccount("marker")
    defer { CardCredentialStore.deleteShared(account: account) }

    #expect(CardCredentialStore.writeShared(Self.emptyMarker, account: account) == errSecSuccess)
    #expect(CardCredentialStore.existsShared(account: account))
    let stored = try #require(CardCredentialStore.readShared(account: account))
    #expect(stored.isEmpty)

    CardCredentialStore.deleteShared(account: account)
    #expect(!CardCredentialStore.existsShared(account: account))
    #expect(CardCredentialStore.readShared(account: account) == nil)
  }

  @Test("Distinct accounts remain isolated across unshared and shared entry points")
  internal func distinctAccountsStayIsolated() {
    #expect(TestCredentialEnvironment.isTestMode)
    let unsharedAccount = Self.uniqueAccount("isolated-unshared")
    let sharedAccount = Self.uniqueAccount("isolated-shared")
    defer {
      CardCredentialStore.delete(account: unsharedAccount)
      CardCredentialStore.deleteShared(account: sharedAccount)
    }

    #expect(CardCredentialStore.write(Self.firstValue, account: unsharedAccount) == errSecSuccess)
    #expect(
      CardCredentialStore.writeShared(Self.secondValue, account: sharedAccount) == errSecSuccess)

    #expect(CardCredentialStore.read(account: unsharedAccount) == Self.firstValue)
    #expect(CardCredentialStore.readShared(account: sharedAccount) == Self.secondValue)

    CardCredentialStore.delete(account: unsharedAccount)
    #expect(!CardCredentialStore.exists(account: unsharedAccount))
    #expect(CardCredentialStore.existsShared(account: sharedAccount))
  }

  @Test("Query coordinates scope service, synchronization, data protection, and access group")
  internal func queryCoordinatesFollowAccessGroup() {
    let account = Self.uniqueAccount("coordinates")
    let sampleGroup = Self.sampleGroupPrefix + CardCredentialStore.sharedKeychainGroupSuffix

    let base = CardCredentialStore.query(account: account)
    #expect(base[kSecClass as String] as? String == kSecClassGenericPassword as String)
    #expect(CardCredentialStore.service.hasPrefix(Self.namespacePrefix))
    #expect(base[kSecAttrService as String] as? String == CardCredentialStore.service)
    #expect(base[kSecAttrAccount as String] as? String == account)
    #expect(base[kSecAttrSynchronizable as String] as? Bool == false)
    #expect(
      base[kSecUseDataProtectionKeychain as String] as? Bool
        == KeychainPlatform.usesDataProtection)
    #expect(base[kSecAttrAccessGroup as String] == nil)

    let ungrouped = CardCredentialStore.query(account: account, accessGroup: nil)
    #expect(ungrouped.count == base.count)
    #expect(ungrouped[kSecClass as String] as? String == kSecClassGenericPassword as String)
    #expect(ungrouped[kSecAttrService as String] as? String == CardCredentialStore.service)
    #expect(ungrouped[kSecAttrAccount as String] as? String == account)
    #expect(ungrouped[kSecAttrSynchronizable as String] as? Bool == false)
    #expect(
      ungrouped[kSecUseDataProtectionKeychain as String] as? Bool
        == KeychainPlatform.usesDataProtection)
    #expect(ungrouped[kSecAttrAccessGroup as String] == nil)

    let grouped = CardCredentialStore.query(account: account, accessGroup: sampleGroup)
    #expect(grouped[kSecAttrAccessGroup as String] as? String == sampleGroup)
    #expect(grouped[kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(grouped[kSecAttrSynchronizable as String] as? Bool == false)
  }
}
