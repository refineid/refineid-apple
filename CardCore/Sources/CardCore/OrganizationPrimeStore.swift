// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// The organization primes, one per card model.
///
/// A card on the antenna cannot be told apart from another card of its
/// model before PACE, and PACE needs the PIN, so the record is found by
/// the model alone: the historical bytes of the answer to reset, which an
/// organization card carries unchanged on both interfaces (Documentation/
/// card-types.md), or, on the phone's own antenna, whose answer carries
/// none, the whole answer. The newest read of a model replaces the one
/// before it. The card that then opens PACE proves its chip serial over
/// the secure channel, and a different card is refused before it signs.
///
/// The records live under their own keychain service in the
/// `fi.refineid` namespace (AGENTS.md Rule #4), in the keychain group the
/// app and the token driver share: the driver writes and reads them, and
/// the app's reset forgets them. No enumeration of the citizen primes
/// meets them.
public enum OrganizationPrimeStore {
  /// The keychain service the records live under.
  internal static let service = "fi.refineid.organization-prime"

  /// The namespace of a record's account keyed by historical bytes.
  private static let accountPrefix = "refineid-organization-prime-historical-sha256-"

  /// The namespace of a record's account keyed by the whole answer to
  /// reset, for an interface whose answer carries no historical bytes.
  private static let wholeAnswerAccountPrefix = "refineid-organization-prime-atr-sha256-"

  /// Formats one digest byte as two lowercase hexadecimal digits.
  private static let byteHexFormat = "%02x"

  /// The account for the card model an answer to reset names, or nil for
  /// an empty one.
  ///
  /// The historical bytes name the model where the answer carries them. The
  /// answer the phone's own antenna reports for an organization card
  /// carries none (observed on hardware), so there the whole answer, which
  /// the phone reports the same at every arrival, names it instead.
  private static func account(answerToReset: Data) -> String? {
    guard !answerToReset.isEmpty else { return nil }
    if let parsed = AnswerToReset(bytes: answerToReset), !parsed.historicalBytes.isEmpty {
      return Self.accountPrefix + Self.digest(Data(parsed.historicalBytes))
    }
    return Self.wholeAnswerAccountPrefix + Self.digest(answerToReset)
  }

  /// SHA-256 of `bytes` as lowercase hexadecimal.
  private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes)
      .map { byte in String(format: Self.byteHexFormat, byte) }
      .joined()
  }

  /// Keeps `prime` for the card model `answerToReset` names.
  ///
  /// It replaces the one before it. Answers the keychain's status:
  /// `errSecParam` when the answer to reset is empty or the record does
  /// not encode.
  @discardableResult
  public static func store(_ prime: OrganizationPrime, answerToReset: Data) -> OSStatus {
    guard
      let account = account(answerToReset: answerToReset),
      let payload = try? JSONEncoder().encode(prime)
    else {
      return errSecParam
    }
    let coordinates = query(account: account)
    let replacement = [kSecValueData as String: payload]
    let updated = SecItemUpdate(coordinates as CFDictionary, replacement as CFDictionary)
    guard updated == errSecItemNotFound else { return updated }
    var insertion = coordinates
    insertion[kSecValueData as String] = payload
    insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(insertion as CFDictionary, nil)
  }

  /// The prime for the card model `answerToReset` names, or nil.
  ///
  /// A stored record is re-validated through the initializer rather than
  /// trusted.
  public static func read(answerToReset: Data) -> OrganizationPrime? {
    guard let account = account(answerToReset: answerToReset) else { return nil }
    return read(account: account)
  }

  /// Every stored prime, each re-validated through the initializer; an
  /// undecodable record is skipped.
  public static func storedPrimes() -> [OrganizationPrime] {
    var search = query(account: nil)
    search[kSecMatchLimit as String] = kSecMatchLimitAll
    search[kSecReturnAttributes as String] = true
    var items: CFTypeRef?
    guard
      SecItemCopyMatching(search as CFDictionary, &items) == errSecSuccess,
      let found = items as? [[String: Any]]
    else {
      return []
    }
    return found.compactMap { attributes in
      guard let account = attributes[kSecAttrAccount as String] as? String else { return nil }
      return read(account: account)
    }
  }

  /// The record under `account`, re-validated, or nil.
  private static func read(account: String) -> OrganizationPrime? {
    var search = query(account: account)
    search[kSecReturnData as String] = true
    search[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard
      SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let stored = try? JSONDecoder().decode(OrganizationPrime.self, from: data)
    else {
      return nil
    }
    return OrganizationPrime(
      certificate: stored.certificateDER,
      issuer: stored.issuerDER,
      signatureCertificate: stored.signatureCertificateDER,
      chipSerial: stored.chipSerial
    )
  }

  /// Removes every record.
  public static func forgetAll() {
    SecItemDelete(query(account: nil) as CFDictionary)
  }

  /// Removes every record of the card with this chip serial.
  public static func forget(serial: ChipSerial) {
    var search = query(account: nil)
    search[kSecMatchLimit as String] = kSecMatchLimitAll
    search[kSecReturnAttributes as String] = true
    var items: CFTypeRef?
    guard
      SecItemCopyMatching(search as CFDictionary, &items) == errSecSuccess,
      let found = items as? [[String: Any]]
    else {
      return
    }
    for attributes in found {
      guard let account = attributes[kSecAttrAccount as String] as? String else { continue }
      var read = query(account: account)
      read[kSecReturnData as String] = true
      read[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let decoded =
        SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess
        ? (item as? Data).flatMap { try? JSONDecoder().decode(OrganizationPrime.self, from: $0) }
        : nil
      if decoded == nil || decoded?.chipSerial == serial {
        SecItemDelete(query(account: account) as CFDictionary)
      }
    }
  }

  /// Item coordinates of one record, or of every record when `account`
  /// is nil, in the group the app and the driver share.
  ///
  /// A group opts into the data-protection keychain, which the group
  /// needs; without one the platform's default keychain is used.
  private static func query(account: String?) -> [String: Any] {
    var coordinates: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: false,
    ]
    if let account {
      coordinates[kSecAttrAccount as String] = account
    }
    if let group = CardCredentialStore.sharedKeychainGroup {
      coordinates[kSecAttrAccessGroup as String] = group
      coordinates[kSecUseDataProtectionKeychain as String] = true
    } else if KeychainPlatform.usesDataProtection {
      coordinates[kSecUseDataProtectionKeychain as String] = true
    }
    return coordinates
  }
}
