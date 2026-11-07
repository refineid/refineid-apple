// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// The keychain writes of ``RappDeviceVault``, each answering the
/// keychain's own status.
internal struct RappVaultKeychainWrites {
  /// The system keychain.
  internal static var system: Self {
    Self(
      add: { SecItemAdd($0 as CFDictionary, nil) },
      update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
      delete: { SecItemDelete($0 as CFDictionary) })
  }

  internal let add: ([String: Any]) -> OSStatus
  internal let update: ([String: Any], [String: Any]) -> OSStatus
  internal let delete: ([String: Any]) -> OSStatus
}
