// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Device-bound storage for RAPP pair records and the selected pairing.
///
/// Every public mutation maps to one Keychain add or update. Removing a pair
/// deletes the Keychain item so the same devices can pair again. Nothing of
/// an operation is stored: it lives and ends with its session (RAPP
/// v26.10.29 §8.1 item 3).
public final class RappDeviceVault: @unchecked Sendable {
  /// Storage failures surfaced by vault operations.
  public enum Failure: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case duplicate
    case malformed
    case notFound
    case unavailable(OSStatus)

    /// A localized description of the vault error suitable for display.
    public var errorDescription: String? {
      description
    }

    /// A text representation describing the failure and its underlying code.
    public var description: String {
      switch self {
      case .duplicate:
        return "Duplicate item in device vault"
      case .malformed:
        return "Malformed item in device vault"
      case .notFound:
        return "Item not found in device vault"
      case .unavailable(let status):
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Device vault unavailable: \(message) (\(status))"
      }
    }
  }

  internal enum PairState: String, Codable {
    case active = "active"
    case revoked = "revoked"
  }

  internal struct PairMarker: Codable {
    internal let state: PairState
    internal let revokedAtMilliseconds: UInt64?
  }

  internal struct Namespace {
    internal let pair: String
    internal let selection: String

    internal init(prefix: String) {
      pair = "\(prefix).pair"
      selection = "\(prefix).selection"
    }
  }

  internal enum SelectionAccount {
    internal static let current = "current"
  }

  internal enum IdentifierSize {
    internal static let pair = 16
  }

  /// The keychain service namespace holding pairs, selection, and device
  /// identity.
  public static let serviceNamespace = "fi.refineid.rapp"

  internal let accessGroup: String?
  internal let namespace: Namespace
  private let lock = NSLock()
  internal let encoder: PropertyListEncoder
  internal let decoder = PropertyListDecoder()
  internal var inMemoryStore: [String: [String: [String: Any]]] = [:]

  /// Opens the production vault in the keychain group the app shares
  /// with its token extensions.
  ///
  /// The remote-card token extension reads its pairing's keys from this
  /// group when it dials the phone, so on macOS the vault is in the
  /// data-protection keychain rather than the file keychain, whose items
  /// only the app that created them may read.
  public convenience init() {
    self.init(
      accessGroup: CardCredentialStore.sharedKeychainGroup,
      servicePrefix: Self.serviceNamespace)
  }

  /// Isolates deterministic integration tests from production and from each
  /// simulated peer.
  ///
  /// Production always enters through the public initializer.
  internal init(accessGroup: String?, servicePrefix: String) {
    precondition(!servicePrefix.isEmpty)
    self.accessGroup = accessGroup
    namespace = Namespace(prefix: servicePrefix)
    encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
  }

  /// Stores a new active pair record under its pair identifier.
  public func insertPair(pairID: Data, record: Data) throws {
    try synchronized {
      try insertPairLocked(pairID: pairID, record: record)
    }
  }

  private func insertPairLocked(pairID: Data, record: Data) throws {
    try requireIdentifier(pairID, size: IdentifierSize.pair)
    guard !record.isEmpty else { throw Failure.malformed }
    let marker = try pairMarker(state: .active, revokedAtMilliseconds: nil)
    var item = itemQuery(service: namespace.pair, account: pairID.hexadecimal)
    // After first unlock, as the device identity these records pair with:
    // a launch that follows a boot but not an interactive unlock must read
    // the pairings, not take their locked unreadability for their absence.
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecAttrGeneric as String] = marker
    item[kSecValueData as String] = record
    inMemoryStore[namespace.pair, default: [:]][pairID.hexadecimal] = item
    #if DEBUG
      if TestCredentialEnvironment.isTestMode { return }
    #endif
    let status = SecItemAdd(item as CFDictionary, nil)
    #if DEBUG
      print("[RappDeviceVault] insertPair status: \(status)")
      fflush(stdout)
    #endif
    switch status {
    case errSecSuccess:
      return

    case errSecDuplicateItem:
      let attributes: [String: Any] = [
        kSecAttrGeneric as String: marker,
        kSecValueData as String: record,
      ]
      try updateExisting(
        service: namespace.pair,
        account: pairID.hexadecimal,
        attributes: attributes
      )

    default:
      if Self.isInteractionNotAllowed(status) { return }
      throw Failure.unavailable(status)
    }
  }

  /// Writes the confirmed pairing, or the forgotten one, over the record
  /// stored under the same identifier (RAPP v26.10.29 §4.3 item 4, §4.6
  /// item 2).
  public func replacePair(pairID: Data, record: Data) throws {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      guard !record.isEmpty else { throw Failure.malformed }
      let item = try loadOne(service: namespace.pair, account: pairID.hexadecimal)
      guard !item.isEmpty, try decodePairMarker(item).state == .active else {
        throw Failure.notFound
      }
      try updateExisting(
        service: namespace.pair,
        account: pairID.hexadecimal,
        attributes: [kSecValueData as String: record])
    }
  }

  /// Returns the pair record, or nil when it is absent or revoked.
  public func loadPair(pairID: Data) throws -> Data? {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      let item = try loadOne(service: namespace.pair, account: pairID.hexadecimal)
      guard !item.isEmpty else { return nil }
      let marker = try decodePairMarker(item)
      guard marker.state == .active else { return nil }
      guard let record = item[kSecValueData as String] as? Data, !record.isEmpty else {
        throw Failure.malformed
      }
      return record
    }
  }

  /// Reports whether a revoked pair marker is stored for the identifier.
  public func pairIsRevoked(pairID: Data) throws -> Bool {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      let item = try loadOne(service: namespace.pair, account: pairID.hexadecimal)
      guard !item.isEmpty else { return false }
      return try decodePairMarker(item).state == .revoked
    }
  }

  /// Lists the identifiers of stored pairs that are not revoked.
  public func activePairIDs() throws -> [Data] {
    try synchronized {
      try loadAll(service: namespace.pair).compactMap { item in
        let marker = try decodePairMarker(item)
        guard marker.state == .active else { return nil }
        guard
          let account = item[kSecAttrAccount as String] as? String,
          let pairID = Data(strictHexadecimal: account),
          pairID.count == IdentifierSize.pair
        else {
          throw Failure.malformed
        }
        return pairID
      }
    }
  }

  /// Returns the identifier of the currently selected pair, if any.
  public func selectedPairID() throws -> Data? {
    try synchronized {
      let item = try loadOne(
        service: namespace.selection,
        account: SelectionAccount.current
      )
      guard !item.isEmpty else { return nil }
      guard
        let pairID = item[kSecValueData as String] as? Data,
        pairID.count == IdentifierSize.pair
      else { throw Failure.malformed }
      return pairID
    }
  }

  /// Marks an active pair as the current selection.
  public func selectPair(pairID: Data) throws {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      let item = try loadOne(
        service: namespace.pair,
        account: pairID.hexadecimal
      )
      guard !item.isEmpty, try decodePairMarker(item).state == .active else {
        throw Failure.notFound
      }
      try upsert(
        service: namespace.selection,
        account: SelectionAccount.current,
        attributes: [kSecValueData as String: pairID]
      )
    }
  }

  /// Removes the current pair selection, if any.
  public func clearSelectedPair() throws {
    try synchronized {
      try deleteItem(service: namespace.selection, account: SelectionAccount.current)
    }
  }

  /// Deletes the pair record.
  public func revokePair(pairID: Data, revokedAtMilliseconds _: UInt64) throws {
    try synchronized {
      try requireIdentifier(pairID, size: IdentifierSize.pair)
      try deleteItem(service: namespace.pair, account: pairID.hexadecimal)
    }
  }

  internal func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

extension Data {
  private static let hexadecimalDigitsPerByte = 2
  private static let hexadecimalRadix = 16

  internal var hexadecimal: String {
    map { String(format: "%02x", $0) }.joined()
  }

  internal init?(strictHexadecimal value: String) {
    guard value.count.isMultiple(of: Self.hexadecimalDigitsPerByte) else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(value.count / Self.hexadecimalDigitsPerByte)
    var index = value.startIndex
    while index < value.endIndex {
      let next = value.index(index, offsetBy: Self.hexadecimalDigitsPerByte)
      guard let byte = UInt8(value[index..<next], radix: Self.hexadecimalRadix) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}
