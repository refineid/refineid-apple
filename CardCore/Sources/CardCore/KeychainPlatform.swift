// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which keychain the card stores use on this platform.
///
/// On iOS this is true: every store that consults it sets
/// `kSecUseDataProtectionKeychain`, so its items are data-protection
/// keychain items and their `kSecAttrAccessible` value applies.
///
/// On macOS this is false. A store that names
/// ``CardCredentialStore/sharedKeychainGroup`` sets
/// `kSecUseDataProtectionKeychain` itself for those items: the shared
/// ``CardCredentialStore`` items, ``OrganizationPrimeStore`` and
/// ``TrustRootsCache``, while the entitlement names the group. Every other
/// store that consults this flag -- ``PrimeStore``, ``CardTransportStore``,
/// the stored card access number and ``RappDeviceVault`` without an access
/// group -- writes to the file-based keychain. Those items set
/// `kSecAttrSynchronizable` false, and Apple's `kSecAttrAccessible`
/// reference says the attribute applies to macOS keychain items only when
/// `kSecUseDataProtectionKeychain`, `kSecAttrSynchronizable` or both are
/// true, so neither its unlock condition nor `ThisDeviceOnly` applies to
/// them.
internal enum KeychainPlatform {
  /// Whether `kSecUseDataProtectionKeychain` may be requested.
  internal static var usesDataProtection: Bool {
    #if os(iOS)
      true
    #else
      false
    #endif
  }
}
