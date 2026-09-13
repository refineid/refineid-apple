// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

extension RappDeviceVault {
  private static let cssmErrNoUserInteraction: OSStatus = -2_147_415_840

  internal static func isInteractionNotAllowed(_ status: OSStatus) -> Bool {
    status == errSecInteractionNotAllowed
      || status == cssmErrNoUserInteraction
      || status == errSecAuthFailed
      || status == errSecMissingEntitlement
  }

  internal func persistProxyValue(
    pairID: Data,
    operationID: Data,
    record: Data,
    retainedResult: RetainedResultMutation
  ) throws {
    try synchronized {
      try requireOperationIdentifiers(pairID: pairID, operationID: operationID)
      guard !record.isEmpty else { throw Failure.malformed }
      let service = operationService(namespace: namespace.proxy, pairID: pairID)
      let account = operationID.hexadecimal
      var attributes: [String: Any] = [kSecAttrGeneric as String: record]
      switch retainedResult {
      case .preserve:
        try updateExisting(service: service, account: account, attributes: attributes)

      case .replace(let result):
        attributes[kSecValueData as String] = result ?? StoredValue.noRetainedResult
        try upsert(service: service, account: account, attributes: attributes)
      }
    }
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

  internal func operationService(namespace: String, pairID: Data) -> String {
    "\(namespace).\(pairID.hexadecimal)"
  }

  internal func requireOperationIdentifiers(pairID: Data, operationID: Data) throws {
    try requireIdentifier(pairID, size: IdentifierSize.pair)
    try requireIdentifier(operationID, size: IdentifierSize.operation)
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
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  internal func itemQuery(service: String, account: String) -> [String: Any] {
    var query = itemQuery(service: service)
    query[kSecAttrAccount as String] = account
    return query
  }

  internal func loadOne(service: String, account: String) throws -> [String: Any] {
    if let inMemory = inMemoryStore[service]?[account] {
      return inMemory
    }
    if TestCredentialEnvironment.isTestMode {
      return [:]
    }
    var query = itemQuery(service: service, account: account)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var output: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &output)
    switch status {
    case errSecSuccess:
      guard let item = output as? [String: Any] else { throw Failure.malformed }
      return item

    case errSecItemNotFound:
      return [:]

    default:
      if Self.isInteractionNotAllowed(status) {
        return [:]
      }
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

  private func inMemoryItems(for service: String) -> [[String: Any]] {
    Array((inMemoryStore[service] ?? [:]).values)
  }

  private func mergeInMemory(items: [[String: Any]], service: String) -> [[String: Any]] {
    var combined = items
    guard let inMem = inMemoryStore[service] else { return combined }
    for (acc, val) in inMem {
      let present = combined.contains { existing in
        (existing[kSecAttrAccount as String] as? String) == acc
      }
      if !present {
        combined.append(val)
      }
    }
    return combined
  }

  internal func loadAll(service: String) throws -> [[String: Any]] {
    if TestCredentialEnvironment.isTestMode {
      return sortItems(inMemoryItems(for: service))
    }
    var query = itemQuery(service: service)
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitAll
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
      return sortItems(mergeInMemory(items: items, service: service))

    case errSecItemNotFound:
      return sortItems(inMemoryItems(for: service))

    default:
      if Self.isInteractionNotAllowed(status) {
        return sortItems(inMemoryItems(for: service))
      }
      throw Failure.unavailable(status)
    }
  }

  internal func updateExisting(
    service: String,
    account: String,
    attributes: [String: Any]
  ) throws {
    if inMemoryStore[service]?[account] != nil || TestCredentialEnvironment.isTestMode {
      // Mirror SecItemUpdate merge semantics: fold the attributes into the
      // stored item and keep its account, so later reads see one whole item.
      var stored = inMemoryStore[service]?[account] ?? [:]
      stored[kSecAttrAccount as String] = account
      for (key, value) in attributes {
        stored[key] = value
      }
      inMemoryStore[service, default: [:]][account] = stored
      if TestCredentialEnvironment.isTestMode { return }
    }
    let status = SecItemUpdate(
      itemQuery(service: service, account: account) as CFDictionary,
      attributes as CFDictionary)
    switch status {
    case errSecSuccess:
      return

    case errSecItemNotFound:
      if inMemoryStore[service]?[account] != nil {
        return
      }
      throw Failure.notFound

    default:
      if Self.isInteractionNotAllowed(status) {
        inMemoryStore[service, default: [:]][account] = attributes
        return
      }
      throw Failure.unavailable(status)
    }
  }

  internal func upsert(
    service: String,
    account: String,
    attributes: [String: Any]
  ) throws {
    inMemoryStore[service, default: [:]][account] = attributes
    if TestCredentialEnvironment.isTestMode { return }
    let query = itemQuery(service: service, account: account)
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess || Self.isInteractionNotAllowed(updateStatus) { return }
    guard updateStatus == errSecItemNotFound else {
      throw Failure.unavailable(updateStatus)
    }

    var item = query
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    for (key, value) in attributes {
      item[key] = value
    }
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    if addStatus == errSecSuccess || Self.isInteractionNotAllowed(addStatus) { return }
    if addStatus == errSecDuplicateItem {
      let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if retryStatus == errSecSuccess || Self.isInteractionNotAllowed(retryStatus) { return }
      throw Failure.unavailable(retryStatus)
    }
    throw Failure.unavailable(addStatus)
  }

  internal func deleteItem(service: String, account: String) throws {
    inMemoryStore[service]?.removeValue(forKey: account)
    if TestCredentialEnvironment.isTestMode { return }
    let query = itemQuery(service: service, account: account)
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

  internal func deleteAll(service: String) throws {
    inMemoryStore.removeValue(forKey: service)
    if TestCredentialEnvironment.isTestMode { return }
    let query = itemQuery(service: service)
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
