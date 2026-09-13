// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

extension TrustRootsCache {
  /// Query coordinates for a persistent CA certificate item.
  internal static func query(account: String) -> [String: Any] {
    var coordinates: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
    if let group = CardCredentialStore.sharedKeychainGroup {
      coordinates[kSecAttrAccessGroup as String] = group
      coordinates[kSecUseDataProtectionKeychain as String] = true
      coordinates[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    } else if KeychainPlatform.usesDataProtection {
      coordinates[kSecUseDataProtectionKeychain as String] = true
      coordinates[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    return coordinates
  }

  /// Query template for matching CA certificate items without an account restriction.
  internal static func baseSearchQuery() -> [String: Any] {
    var search: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: false,
    ]
    if let group = CardCredentialStore.sharedKeychainGroup {
      search[kSecAttrAccessGroup as String] = group
      search[kSecUseDataProtectionKeychain as String] = true
    } else if KeychainPlatform.usesDataProtection {
      search[kSecUseDataProtectionKeychain as String] = true
    }
    return search
  }

  /// Verifies that certificate bytes are within their validity window and represent a trusted root or CA.
  internal static func isAuthenticAndValid(_ der: Data) -> Bool {
    guard let window = CertificateValidity.window(inDer: der) else {
      return false
    }
    let now = Date()
    guard window.notBefore <= now, now < window.notAfter else {
      return false
    }
    let fingerprint = Data(SHA256.hash(data: der))
    let rsa = Data(pinnedDvvG3RsaSha256)
    let ecc = Data(pinnedDvvG3EccSha256)
    let isPinnedRoot = fingerprint == rsa || fingerprint == ecc
    let isCa = CertificateFacts(der: der)?.isCertificateAuthority == true
    return isPinnedRoot || isCa
  }

  /// Saves a newly registered certificate to persistent storage if authentic and unexpired.
  internal static func persistCertificate(_ der: Data) {
    guard isAuthenticAndValid(der) else {
      return
    }
    let fingerprint = Data(SHA256.hash(data: der))
    let account = fingerprint.map { String(format: "%02x", $0) }.joined()

    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.storeTrustedCa(der, account: account)
      return
    }

    var coordinates = query(account: account)
    coordinates[kSecValueData as String] = der
    let status = SecItemAdd(coordinates as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateQuery = query(account: account)
      let replacement = [kSecValueData as String: der]
      _ = SecItemUpdate(updateQuery as CFDictionary, replacement as CFDictionary)
    }
  }

  /// Deletes all persistent CA items from Keychain or test store.
  internal static func deletePersistentCas() {
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.forgetAllTrustedCas()
      return
    }
    let deleteQuery = baseSearchQuery()
    _ = SecItemDelete(deleteQuery as CFDictionary)
  }

  /// Loads persisted certificates on startup, purging any expired or invalid ones.
  internal func loadPersistedCas() {
    if TestCredentialEnvironment.isTestMode {
      let items = TestCredentialEnvironment.allTrustedCas().sorted { $0.account < $1.account }
      for (account, data) in items {
        if !Self.isAuthenticAndValid(data) {
          TestCredentialEnvironment.deleteTrustedCa(account: account)
          continue
        }
        loadValidCertificate(data)
      }
      return
    }

    var search = Self.baseSearchQuery()
    search[kSecMatchLimit as String] = kSecMatchLimitAll
    search[kSecReturnData as String] = true
    search[kSecReturnAttributes as String] = true

    var result: CFTypeRef?
    guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
      let items = result as? [[String: Any]]
    else {
      return
    }

    let mapped = items.compactMap { item -> (account: String, data: Data)? in
      guard
        let account = item[kSecAttrAccount as String] as? String,
        let data = item[kSecValueData as String] as? Data
      else {
        return nil
      }
      return (account, data)
    }
    let sortedItems = mapped.sorted { $0.account < $1.account }

    for (account, data) in sortedItems {
      if !Self.isAuthenticAndValid(data) {
        let deleteQuery = Self.query(account: account)
        _ = SecItemDelete(deleteQuery as CFDictionary)
        continue
      }
      loadValidCertificate(data)
    }
  }
}
