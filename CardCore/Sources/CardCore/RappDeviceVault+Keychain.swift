// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

extension RappDeviceVault {
  private static let cssmErrNoUserInteraction: OSStatus = -2_147_415_840

  /// Whether a read found the keychain closed to this process for now.
  ///
  /// That is a locked keychain, or an item it may not read without a
  /// prompt. Reads only: a write answering any of these did not store
  /// anything. `errSecMissingEntitlement` is not among them, since no later
  /// attempt by the same process can succeed.
  internal static func isUnreadableForNow(_ status: OSStatus) -> Bool {
    status == errSecInteractionNotAllowed
      || status == cssmErrNoUserInteraction
      || status == errSecAuthFailed
  }

  internal func pairMarker(
    state: PairState,
    revokedAtMilliseconds: UInt64?
  ) throws -> Data {
    do {
      return try encoder.encode(
        PairMarker(state: state, revokedAtMilliseconds: revokedAtMilliseconds))
    } catch {
      throw Failure.malformed
    }
  }

  internal func decodePairMarker(_ item: [String: Any]) throws -> PairMarker {
    guard let data = item[kSecAttrGeneric as String] as? Data else {
      throw Failure.malformed
    }
    do {
      return try decoder.decode(PairMarker.self, from: data)
    } catch {
      throw Failure.malformed
    }
  }

  internal func requireIdentifier(_ value: Data, size: Int) throws {
    guard value.count == size else { throw Failure.malformed }
  }

  internal func itemQuery(service: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
    // The file keychain drops an access group, so a grouped item lives in
    // the data-protection keychain on every platform.
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  internal func itemQuery(service: String, account: String) -> [String: Any] {
    var query = itemQuery(service: service)
    query[kSecAttrAccount as String] = account
    return query
  }

  internal func loadOne(service: String, account: String) throws -> [String: Any] {
    #if DEBUG
      if TestCredentialEnvironment.isTestMode {
        return testKeychain.items[service]?[account] ?? [:]
      }
    #endif
    var query = itemQuery(service: service, account: account)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    switch status {
    case errSecSuccess:
      guard let item = output as? [String: Any] else { throw Failure.malformed }
      return item

    case errSecItemNotFound:
      return [:]

    default:
      if Self.isUnreadableForNow(status) {
        return [:]
      }
      throw Failure.unavailable(status)
    }
  }

  /// The item, empty when the keychain answers it is absent; every other
  /// answer throws, one that only means "not now" included.
  internal func loadOneStrictly(service: String, account: String) throws -> [String: Any] {
    #if DEBUG
      if TestCredentialEnvironment.isTestMode {
        if let status = testKeychain.readRefusal { throw Failure.unavailable(status) }
        return testKeychain.items[service]?[account] ?? [:]
      }
    #endif
    var query = itemQuery(service: service, account: account)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    switch status {
    case errSecSuccess:
      guard let item = output as? [String: Any] else { throw Failure.malformed }
      return item

    case errSecItemNotFound:
      return [:]

    default:
      throw Failure.unavailable(status)
    }
  }

  private func sortItems(_ items: [[String: Any]]) -> [[String: Any]] {
    items.sorted { first, second in
      let firstAccount = first[kSecAttrAccount as String] as? String ?? ""
      let secondAccount = second[kSecAttrAccount as String] as? String ?? ""
      return firstAccount < secondAccount
    }
  }

  internal func loadAll(service: String) throws -> [[String: Any]] {
    #if DEBUG
      if TestCredentialEnvironment.isTestMode {
        return sortItems(Array((testKeychain.items[service] ?? [:]).values))
      }
    #endif
    var query = itemQuery(service: service)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    #if DEBUG
      print("[RappDeviceVault] loadAll(service: \(service)) status: \(status)")
      fflush(stdout)
    #endif
    switch status {
    case errSecSuccess:
      guard let attributes = output as? [[String: Any]] else { throw Failure.malformed }
      var items: [[String: Any]] = []
      for attribute in attributes {
        guard let account = attribute[kSecAttrAccount as String] as? String else {
          throw Failure.malformed
        }
        let loaded = try loadOne(service: service, account: account)
        if !loaded.isEmpty {
          items.append(loaded)
        }
      }
      return sortItems(items)

    case errSecItemNotFound:
      return []

    default:
      if Self.isUnreadableForNow(status) {
        return []
      }
      throw Failure.unavailable(status)
    }
  }

  internal func updateExisting(
    service: String,
    account: String,
    attributes: [String: Any]
  ) throws {
    let status = writes.update(itemQuery(service: service, account: account), attributes)
    switch status {
    case errSecSuccess:
      return

    case errSecItemNotFound:
      throw Failure.notFound

    default:
      throw Failure.unavailable(status)
    }
  }

  internal func upsert(
    service: String,
    account: String,
    attributes: [String: Any]
  ) throws {
    let query = itemQuery(service: service, account: account)
    let updateStatus = writes.update(query, attributes)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw Failure.unavailable(updateStatus)
    }

    var item = query
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    for (key, value) in attributes {
      item[key] = value
    }
    let addStatus = writes.add(item)
    if addStatus == errSecSuccess { return }
    guard addStatus == errSecDuplicateItem else {
      throw Failure.unavailable(addStatus)
    }
    let retryStatus = writes.update(query, attributes)
    guard retryStatus == errSecSuccess else {
      throw Failure.unavailable(retryStatus)
    }
  }

  internal func deleteItem(service: String, account: String) throws {
    try requireDeleted(itemQuery(service: service, account: account))
  }

  internal func deleteAll(service: String) throws {
    try requireDeleted(itemQuery(service: service))
  }

  /// Deletes what `query` names; an item already absent counts as deleted.
  internal func requireDeleted(_ query: [String: Any]) throws {
    var status = writes.delete(query)
    #if os(macOS)
      if status == errSecInvalidOwnerEdit {
        status = Self.deleteKeychainItemRef(query: query)
      }
    #endif
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure.unavailable(status)
    }
  }
}
