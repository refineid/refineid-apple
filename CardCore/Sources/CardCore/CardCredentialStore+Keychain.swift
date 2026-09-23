// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

extension CardCredentialStore {
  /// Suffix of the keychain group the app and its extensions share.
  internal static let sharedKeychainGroupSuffix = "fi.refineid.ReFineID"

  /// The shared group, or nil where no entitlement names one.
  ///
  /// Read from this binary's own entitlements, so no team identifier
  /// is written in source. Nil keeps the platform's default behavior.
  internal static var sharedKeychainGroup: String? {
    #if os(macOS)
      guard let task = SecTaskCreateFromSelf(nil) else { return nil }
      var error: Unmanaged<CFError>?
      let value = SecTaskCopyValueForEntitlement(
        task, "keychain-access-groups" as CFString, &error)
      let groups = value as? [String] ?? []
      return groups.first { $0.hasSuffix(sharedKeychainGroupSuffix) }
    #else
      return nil
    #endif
  }

  /// The platform half of the above: iOS shares a keychain access group
  /// with its extensions and needs no second copy of the number, so it
  /// does not make one.
  @discardableResult
  internal static func publishToDriver(digits: String) -> Bool {
    #if os(macOS)
      return CardCanOffer.publish(digits: digits)
    #else
      return false
    #endif
  }

  /// Item coordinates shared by every operation.
  ///
  /// `ThisDeviceOnly` keeps these out of backups and off other devices;
  /// `synchronizable` false keeps them out of iCloud. Both are required
  /// -- neither implies the other.
  internal static func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      // iOS only. On macOS the data-protection keychain requires a
      // keychain-access-group entitlement, and asking for one there
      // fails signing on a development profile -- every store call then
      // answers errSecMissingEntitlement and the app cannot keep a card
      // access number at all. The file keychain needs no entitlement and
      // is protected by the same login keychain the rest of the system
      // uses.
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
  }

  /// The same coordinates in one shared access group.
  ///
  /// Only new machine-use accounts use this: existing items were
  /// created without a group, and asking for them with one would miss.
  /// A group also opts into the data-protection keychain: the file
  /// keychain silently drops the group, so shared items would land
  /// ungrouped and stay invisible to the other process.
  internal static func query(account: String, accessGroup: String?) -> [String: Any] {
    var coordinates = query(account: account)
    if let accessGroup {
      coordinates[kSecAttrAccessGroup as String] = accessGroup
      coordinates[kSecUseDataProtectionKeychain as String] = true
    }
    return coordinates
  }

  /// Whether an item is present, without authenticating.
  ///
  /// The lookup explicitly skips any interface. A protected item then
  /// answers `errSecInteractionNotAllowed`, which is itself proof that
  /// it exists -- so both that and success count as present, and neither
  /// prompts the holder just to draw a status row.
  internal static func exists(account: String) -> Bool {
    if TestCredentialEnvironment.isTestMode {
      return TestCredentialEnvironment.credentialExists(account: account)
    }
    var query = self.query(account: account)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  /// Reads a value from the shared group both binaries are entitled to.
  internal static func readShared(account: String) -> String? {
    if TestCredentialEnvironment.isTestMode {
      return TestCredentialEnvironment.readCredential(account: account)
    }
    var query = self.query(account: account, accessGroup: sharedKeychainGroup)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Reads a value.
  ///
  /// Nothing in the app calls this to display a value -- it exists so
  /// card setup can use what was entered earlier.
  internal static func read(account: String) -> String? {
    if TestCredentialEnvironment.isTestMode {
      return TestCredentialEnvironment.readCredential(account: account)
    }
    var query = self.query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Writes a value.
  ///
  /// Returns the keychain's own status rather than a bare false, because
  /// a refusal here is not the holder's fault, and telling them their PIN
  /// is invalid when the store merely could not replace an item sends
  /// them looking in the wrong place.
  /// Writes a value into the shared group both binaries are entitled to.
  internal static func writeShared(_ digits: String, account: String) -> OSStatus {
    guard let data = digits.data(using: .utf8) else { return errSecParam }
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.writeCredential(digits, account: account)
      return errSecSuccess
    }
    let coordinates = query(account: account, accessGroup: sharedKeychainGroup)
    let replacement = [kSecValueData as String: data]
    let updated = SecItemUpdate(
      coordinates as CFDictionary,
      replacement as CFDictionary)
    if updated == errSecSuccess { return updated }
    guard updated == errSecItemNotFound else { return updated }

    var insertion = coordinates
    insertion[kSecValueData as String] = data
    insertion[kSecAttrAccessible as String] =
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(insertion as CFDictionary, nil)
  }

  internal static func write(_ digits: String, account: String) -> OSStatus {
    guard let data = digits.data(using: .utf8) else { return errSecParam }
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.writeCredential(digits, account: account)
      return errSecSuccess
    }
    let coordinates = query(account: account)
    let replacement = [kSecValueData as String: data]
    let updated = SecItemUpdate(
      coordinates as CFDictionary,
      replacement as CFDictionary)
    if updated == errSecSuccess { return updated }

    var insertion = coordinates
    insertion[kSecValueData as String] = data
    insertion[kSecAttrAccessible as String] =
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(insertion as CFDictionary, nil)
    if added == errSecDuplicateItem {
      SecItemDelete(coordinates as CFDictionary)
      return SecItemAdd(insertion as CFDictionary, nil)
    }
    return added
  }

  /// Removes an item.
  ///
  /// Deletion does NOT skip the authentication interface. Skipping it
  /// makes a biometrically protected item answer
  /// `errSecInteractionNotAllowed` and survive, after which the add that
  /// follows fails as a duplicate and a perfectly good PIN looks
  /// rejected. Measured: this is exactly why storing PIN1 appeared to do
  /// nothing while storing the ungated access number worked.
  internal static func delete(account: String) {
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.deleteCredential(account: account)
      return
    }
    SecItemDelete(query(account: account) as CFDictionary)
  }

  /// Whether a shared item is present, without authenticating.
  internal static func existsShared(account: String) -> Bool {
    if TestCredentialEnvironment.isTestMode {
      return TestCredentialEnvironment.credentialExists(account: account)
    }
    var query = self.query(account: account, accessGroup: sharedKeychainGroup)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  /// Removes a shared item.
  internal static func deleteShared(account: String) {
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.deleteCredential(account: account)
      return
    }
    let coordinates = query(account: account, accessGroup: sharedKeychainGroup)
    SecItemDelete(coordinates as CFDictionary)
  }
}
