// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

@testable import CardCore

/// Two fresh vaults for one ceremony, and the removal of what they store.
internal struct StreamRelayCeremonyVaults {
  internal let requester: RappDeviceVault
  internal let proxy: RappDeviceVault

  private let prefixes: [String]

  /// Names two vaults nothing else shares.
  internal init(testID: String) {
    let requesterPrefix = "fi.refineid.tests.ceremony.\(testID).requester"
    let proxyPrefix = "fi.refineid.tests.ceremony.\(testID).proxy"
    self.requester = RappDeviceVault(accessGroup: nil, servicePrefix: requesterPrefix)
    self.proxy = RappDeviceVault(accessGroup: nil, servicePrefix: proxyPrefix)
    self.prefixes = [requesterPrefix, proxyPrefix]
  }

  /// Removes everything the ceremony stored.
  internal func clean() {
    for prefix in prefixes {
      for suffix in ["pair", "selection"] {
        SecItemDelete(
          [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(prefix).\(suffix)",
          ] as CFDictionary)
      }
    }
  }
}
