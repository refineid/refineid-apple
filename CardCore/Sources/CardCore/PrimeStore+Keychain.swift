// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

extension PrimeStore {
  /// Every decodable prime.
  internal static func storedItems() -> [StoredItem] {
    #if DEBUG
      if TestCredentialEnvironment.isTestMode {
        return TestCredentialEnvironment.allPrimes().compactMap { account, data in
          guard let identity = try? JSONDecoder().decode(PrimedIdentity.self, from: data) else {
            return nil
          }
          return StoredItem(account: account, identity: identity)
        }
      }
    #endif
    var search: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if KeychainPlatform.usesDataProtection {
      search[kSecUseDataProtectionKeychain as String] = true
      search[kSecAttrSynchronizable as String] = false
      search[kSecReturnData as String] = true
    }
    search[kSecMatchLimit as String] = kSecMatchLimitAll
    search[kSecReturnAttributes as String] = true
    var items: CFTypeRef?
    guard SecItemCopyMatching(search as CFDictionary, &items) == errSecSuccess,
      let found = items as? [[String: Any]]
    else {
      return []
    }
    return found.compactMap { (attributes: [String: Any]) -> StoredItem? in
      guard let account = attributes[kSecAttrAccount as String] as? String else {
        return nil
      }
      if let data = attributes[kSecValueData as String] as? Data,
        let identity = try? JSONDecoder().decode(PrimedIdentity.self, from: data)
      {
        return StoredItem(account: account, identity: identity)
      }
      if let identity = read(account: account) {
        return StoredItem(account: account, identity: identity)
      }
      return nil
    }
  }

  /// Item coordinates shared by every operation on one card's prime.
  ///
  /// The accessibility attribute is deliberately absent here: it belongs
  /// on the write, and a search that filters on it would miss items
  /// written under any other policy instead of replacing them.
  internal static func query(account: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if KeychainPlatform.usesDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
      query[kSecAttrSynchronizable as String] = false
    }
    return query
  }

  /// Removes one account without exposing its coordinates to callers.
  internal static func delete(account: String) {
    #if DEBUG
      if TestCredentialEnvironment.isTestMode {
        TestCredentialEnvironment.deletePrime(account: account)
        return
      }
    #endif
    SecItemDelete(query(account: account) as CFDictionary)
  }

  /// The qualified signature certificate cached for the card opened with
  /// `cardAccessNumber`, or nil when none is cached for that card.
  public static func signatureCertificate(cardAccessNumber: String) -> Data? {
    storedItems().first { $0.identity.can == cardAccessNumber }?.identity.signatureCertDER
  }

  /// Caches the qualified signature certificate in the prime of the card
  /// opened with `cardAccessNumber`.
  ///
  /// The access number binds the certificate to the card: PACE with it
  /// succeeded in the session that read `der`, so the certificate lands
  /// only in the prime of the card that supplied it. False when no prime
  /// holds that access number.
  @discardableResult
  public static func updateSignatureCertificate(_ der: Data, cardAccessNumber: String) -> Bool {
    guard let item = storedItems().first(where: { $0.identity.can == cardAccessNumber }) else {
      return false
    }
    guard
      let updated = PrimedIdentity(
        can: item.identity.can,
        certificate: item.identity.certDER,
        issuer: item.identity.issuerDER,
        tokenSerial: item.identity.tokenSerial,
        activationCheck: item.identity.activationCheck,
        signatureCertificate: der
      )
    else { return false }
    guard let payload = try? JSONEncoder().encode(updated) else { return false }
    #if DEBUG
      if TestCredentialEnvironment.isTestMode {
        TestCredentialEnvironment.storePrime(payload, account: item.account)
        return true
      }
    #endif
    let coordinates = query(account: item.account)
    let replacement = [kSecValueData as String: payload]
    return SecItemUpdate(coordinates as CFDictionary, replacement as CFDictionary)
      == errSecSuccess
  }
}
