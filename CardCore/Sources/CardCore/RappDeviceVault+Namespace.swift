// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import ObjCExceptionGuard
import Security

#if canImport(RappEngine)
  import RappEngine
#endif

extension RappDeviceVault {
  /// The keychains this platform holds items in: macOS keeps a file
  /// keychain beside the data protection keychain, iOS has only the latter.
  private static var dataProtectionKeychains: [Bool] {
    #if os(iOS)
      [true]
    #else
      [false, true]
    #endif
  }

  #if os(macOS)
    @discardableResult
    internal static func deleteKeychainItemRef(query: [String: Any]) -> OSStatus {
      CardCoreDeleteKeychainItemRef(query as CFDictionary)
    }
  #endif

  /// Deletes every generic-password item whose service starts with the
  /// namespace prefix, and returns how many were deleted.
  ///
  /// When `excludingRevocationNotices` is true, unexpired revocation notices
  /// held under the pair service are retained for the remainder of their
  /// 30-day window so offline peers receive `pairing_revoked`.
  ///
  /// Both the file and data-protection stores are swept: shared items land
  /// in the data-protection store while ungrouped items stay in the file
  /// store, and neither query sees the other's items. The synchronizable
  /// filter is omitted so writers that rely on the default are swept too.
  public func deleteServiceNamespace(
    _ prefix: String = "fi.refineid",
    excludingRevocationNotices: Bool = false
  ) throws -> Int {
    try synchronized {
      guard !prefix.isEmpty else { throw Failure.malformed }
      #if DEBUG
        if TestCredentialEnvironment.isTestMode {
          return deleteInMemoryNamespace(
            prefix: prefix, excludingRevocationNotices: excludingRevocationNotices)
        }
      #endif
      return try deleteKeychainNamespace(
        prefix: prefix, excludingRevocationNotices: excludingRevocationNotices)
    }
  }

  /// Deletes every item of this vault's namespace from the macOS file
  /// keychain, and returns how many were deleted.
  ///
  /// A vault in the shared group lives in the data-protection keychain and
  /// never reads the file keychain, so an item there serves nothing, and it
  /// may hold a pairing's private key. A vault with no group answers zero:
  /// the file keychain is where that vault lives. Throws the first failure
  /// after trying every item.
  @discardableResult
  public func deleteFileKeychainStrays() throws -> Int {
    #if os(macOS)
      try synchronized {
        guard accessGroup != nil else { return 0 }
        return try deleteStrays()
      }
    #else
      0
    #endif
  }

  #if os(macOS)
    private func deleteStrays() throws -> Int {
      var deleted = 0
      var firstError: (any Error)?
      for coordinate in try fileKeychainStrayCoordinates() {
        do {
          try deleteNamespacedItem(
            service: coordinate.service, account: coordinate.account, dataProtection: false)
          deleted += 1
        } catch {
          if firstError == nil { firstError = error }
        }
      }
      if let firstError { throw firstError }
      return deleted
    }

    private func fileKeychainStrayCoordinates() throws -> [(service: String, account: String)] {
      #if DEBUG
        if TestCredentialEnvironment.isTestMode {
          return testKeychain.fileKeychainCoordinates(prefix: namespace.services)
        }
      #endif
      return try namespaceCoordinates(prefix: namespace.services, dataProtection: false)
    }
  #endif

  internal func isUnexpiredRevocationNotice(data: Data) -> Bool {
    #if canImport(RappEngine)
      guard let pair = try? RappPairRecord.decode(from: data) else { return false }
      let meta = pair.metadata()
      guard meta.storageConfirmed, meta.forgottenAtMs != nil else { return false }
      return !pair.revocationNoticeExpired(nowMs: RappPlatformClock().wallMilliseconds())
    #else
      return false
    #endif
  }

  private func isPairService(_ service: String) -> Bool {
    service == namespace.pair || service.hasSuffix(".pair")
  }

  private func loadNamespacedItemData(
    service: String, account: String, dataProtection: Bool
  ) throws -> Data? {
    var query = itemQuery(service: service, account: account)
    query[kSecUseDataProtectionKeychain as String] = dataProtection
    query.removeValue(forKey: kSecAttrAccessGroup as String)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    switch status {
    case errSecSuccess:
      return output as? Data
    case errSecItemNotFound:
      return nil
    default:
      throw Failure.unavailable(status)
    }
  }

  private func shouldRetainNotice(
    service: String, account: String, dataProtection: Bool
  ) throws -> Bool {
    guard isPairService(service) else { return false }
    guard
      let data = try loadNamespacedItemData(
        service: service, account: account, dataProtection: dataProtection)
    else { return false }
    return isUnexpiredRevocationNotice(data: data)
  }

  #if DEBUG
    private func deleteInMemoryMap(
      _ map: inout [String: [String: [String: Any]]],
      prefix: String,
      excludingRevocationNotices: Bool
    ) -> Int {
      var deleted = 0
      let services = map.keys.filter { $0.hasPrefix(prefix) }
      for service in services {
        guard let accounts = map[service] else { continue }
        if excludingRevocationNotices, isPairService(service) {
          var remaining: [String: [String: Any]] = [:]
          for (account, item) in accounts {
            if let data = item[kSecValueData as String] as? Data,
              isUnexpiredRevocationNotice(data: data)
            {
              remaining[account] = item
            } else {
              deleted += 1
            }
          }
          if remaining.isEmpty {
            map.removeValue(forKey: service)
          } else {
            map[service] = remaining
          }
        } else {
          deleted += accounts.count
          map.removeValue(forKey: service)
        }
      }
      return deleted
    }

    private func deleteInMemoryNamespace(
      prefix: String,
      excludingRevocationNotices: Bool
    ) -> Int {
      deleteInMemoryMap(
        &testKeychain.items, prefix: prefix, excludingRevocationNotices: excludingRevocationNotices)
        + deleteInMemoryMap(
          &testKeychain.fileKeychain, prefix: prefix,
          excludingRevocationNotices: excludingRevocationNotices)
    }
  #endif

  private func deleteCoordinateItem(
    coordinate: (service: String, account: String),
    dataProtection: Bool,
    excludingRevocationNotices: Bool
  ) throws -> Bool {
    if excludingRevocationNotices,
      try shouldRetainNotice(
        service: coordinate.service,
        account: coordinate.account,
        dataProtection: dataProtection)
    {
      return false
    }
    try deleteNamespacedItem(
      service: coordinate.service,
      account: coordinate.account,
      dataProtection: dataProtection)
    return true
  }

  private func deleteKeychainNamespace(
    prefix: String,
    excludingRevocationNotices: Bool
  ) throws -> Int {
    var deleted = 0
    var firstError: (any Error)?
    for dataProtection in Self.dataProtectionKeychains {
      let coordinates: [(service: String, account: String)]
      do {
        coordinates = try namespaceCoordinates(
          prefix: prefix, dataProtection: dataProtection)
      } catch {
        if firstError == nil { firstError = error }
        continue
      }
      for coordinate in coordinates {
        do {
          if try deleteCoordinateItem(
            coordinate: coordinate,
            dataProtection: dataProtection,
            excludingRevocationNotices: excludingRevocationNotices)
          {
            deleted += 1
          }
        } catch {
          if firstError == nil { firstError = error }
        }
      }
    }
    if let firstError {
      throw firstError
    }
    return deleted
  }

  private func namespaceCoordinates(
    prefix: String, dataProtection: Bool
  ) throws -> [(service: String, account: String)] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnAttributes as String: kCFBooleanTrue as Any,
      kSecUseDataProtectionKeychain as String: dataProtection,
      kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
    ]
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    switch status {
    case errSecSuccess:
      guard let items = output as? [[String: Any]] else { throw Failure.malformed }
      return items.compactMap { item in
        guard let service = item[kSecAttrService as String] as? String,
          service.hasPrefix(prefix),
          let account = item[kSecAttrAccount as String] as? String
        else { return nil }
        return (service: service, account: account)
      }

    case errSecItemNotFound:
      return []

    default:
      #if os(macOS)
        // On macOS the data-protection keychain takes an access-group
        // entitlement; a process without one has no items there to delete.
        if dataProtection, status == errSecMissingEntitlement { return [] }
      #endif
      throw Failure.unavailable(status)
    }
  }

  private func deleteNamespacedItem(
    service: String, account: String, dataProtection: Bool
  ) throws {
    // Skipping items that need authentication UI is a copy-matching
    // option only; a delete carrying it is a parameter error.
    var query = itemQuery(service: service, account: account)
    query[kSecUseDataProtectionKeychain as String] = dataProtection
    query.removeValue(forKey: kSecAttrAccessGroup as String)
    try requireDeleted(query)
  }
}
