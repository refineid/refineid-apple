// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

#if DEBUG
  /// The vault's items under test isolation, answering writes with the
  /// statuses the keychain gives for the same operation.
  ///
  /// Accessed under the vault's lock, like the keychain calls it stands in
  /// for.
  internal final class RappVaultTestKeychain {
    /// One kind of keychain write.
    internal enum Write: Equatable {
      case add
      case update
      case delete
    }

    /// Items by service, then by account.
    internal var items: [String: [String: [String: Any]]] = [:]

    /// Items of the macOS file keychain, by service, then by account; only
    /// a delete naming that keychain reaches them.
    internal var fileKeychain: [String: [String: [String: Any]]] = [:]

    /// The status a strict read is refused with, or nil to let it through.
    internal var readRefusal: OSStatus?

    /// The status a write is refused with, or nil to let it through.
    internal var refusal: (Write) -> OSStatus? = { _ in nil }

    /// Every write attempted, in order.
    internal private(set) var attempts: [Write] = []

    internal var writes: RappVaultKeychainWrites {
      RappVaultKeychainWrites(
        add: { [self] in add($0) },
        update: { [self] in update(query: $0, attributes: $1) },
        delete: { [self] in delete(query: $0) })
    }

    private static func service(_ query: [String: Any]) -> String {
      query[kSecAttrService as String] as? String ?? ""
    }

    private static func account(_ query: [String: Any]) -> String {
      query[kSecAttrAccount as String] as? String ?? ""
    }

    internal func fileKeychainCoordinates(prefix: String) -> [(service: String, account: String)] {
      fileKeychain.filter { $0.key.hasPrefix(prefix) }.flatMap { service, accounts in
        accounts.keys.map { (service: service, account: $0) }
      }
    }

    private func refused(_ write: Write) -> OSStatus? {
      attempts.append(write)
      return refusal(write)
    }

    private func add(_ item: [String: Any]) -> OSStatus {
      if let status = refused(.add) { return status }
      let service = Self.service(item)
      let account = Self.account(item)
      guard items[service]?[account] == nil else { return errSecDuplicateItem }
      items[service, default: [:]][account] = item
      return errSecSuccess
    }

    private func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
      if let status = refused(.update) { return status }
      let service = Self.service(query)
      let account = Self.account(query)
      guard var stored = items[service]?[account] else { return errSecItemNotFound }
      stored.merge(attributes) { _, new in new }
      items[service]?[account] = stored
      return errSecSuccess
    }

    private func delete(query: [String: Any]) -> OSStatus {
      if let status = refused(.delete) { return status }
      let service = Self.service(query)
      if query[kSecUseDataProtectionKeychain as String] as? Bool == false,
        fileKeychain[service]?[Self.account(query)] != nil
      {
        fileKeychain[service]?.removeValue(forKey: Self.account(query))
        return errSecSuccess
      }
      guard query[kSecAttrAccount as String] != nil else {
        return items.removeValue(forKey: service) == nil ? errSecItemNotFound : errSecSuccess
      }
      return items[service]?.removeValue(forKey: Self.account(query)) == nil
        ? errSecItemNotFound : errSecSuccess
    }
  }
#endif
