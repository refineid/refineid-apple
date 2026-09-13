// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

extension RappDeviceVault {
  #if os(macOS)
    @discardableResult
    internal static func deleteKeychainItemRef(query: [String: Any]) -> OSStatus {
      var refQuery = query
      refQuery[kSecReturnRef as String] = true
      var refOutput: CFTypeRef?
      guard SecItemCopyMatching(refQuery as CFDictionary, &refOutput) == errSecSuccess,
        let ref = refOutput,
        CFGetTypeID(ref) == SecKeychainItemGetTypeID()
      else { return errSecItemNotFound }
      let itemRef = unsafeDowncast(ref, to: SecKeychainItem.self)
      return SecKeychainItemDelete(itemRef)
    }
  #endif

  /// Deletes every generic-password item whose service starts with the
  /// namespace prefix, and returns how many were deleted.
  ///
  /// Both the file and data-protection stores are swept: shared items land
  /// in the data-protection store while ungrouped items stay in the file
  /// store, and neither query sees the other's items. The synchronizable
  /// filter is omitted so writers that rely on the default are swept too.
  public func deleteServiceNamespace(_ prefix: String = "fi.refineid") throws -> Int {
    try synchronized {
      guard !prefix.isEmpty else { throw Failure.malformed }
      if TestCredentialEnvironment.isTestMode {
        return deleteInMemoryNamespace(prefix: prefix)
      }
      return try deleteKeychainNamespace(prefix: prefix)
    }
  }

  private func deleteInMemoryNamespace(prefix: String) -> Int {
    let services = inMemoryStore.keys.filter { $0.hasPrefix(prefix) }
    let deleted = services.reduce(0) { $0 + (inMemoryStore[$1]?.count ?? 0) }
    for service in services {
      inMemoryStore.removeValue(forKey: service)
    }
    return deleted
  }

  private func deleteKeychainNamespace(prefix: String) throws -> Int {
    var deleted = 0
    var firstError: (any Error)?
    for dataProtection in [false, true] {
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
          try deleteNamespacedItem(
            service: coordinate.service,
            account: coordinate.account,
            dataProtection: dataProtection)
          deleted += 1
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
      if Self.isInteractionNotAllowed(status) { return [] }
      throw Failure.unavailable(status)
    }
  }

  private func deleteNamespacedItem(
    service: String, account: String, dataProtection: Bool
  ) throws {
    var query = itemQuery(service: service, account: account)
    query[kSecUseDataProtectionKeychain as String] = dataProtection
    query.removeValue(forKey: kSecAttrAccessGroup as String)
    var status = SecItemDelete(query as CFDictionary)
    #if os(macOS)
      if status == errSecInvalidOwnerEdit {
        status = Self.deleteKeychainItemRef(query: query)
      }
    #endif
    if Self.isInteractionNotAllowed(status) { return }
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure.unavailable(status)
    }
  }
}
