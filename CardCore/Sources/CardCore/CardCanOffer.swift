// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// The card access number handoff between the app and the token driver,
/// in the keychain access group both are entitled to.
///
/// Machine use only: opaque account names, and digits never reach a log,
/// a trace or a diagnostics export.
///
/// One active offer plus a per-card library. The driver reads only these
/// slots; the app decides what the offer holds. A card answers with no
/// individual identifier before PACE, so the driver tries every stored
/// number until one mints -- a wrong CAN spends no retry counter, only
/// time, which is why the candidate count stays bounded.
public enum CardCanOffer {
  /// One validated candidate: the digits to spend and their parsed form.
  public struct Candidate {
    /// The six digits, for spending and for remembering on success.
    public let digits: String

    /// The parsed form PACE spends.
    public let number: CardAccessNumber

    /// Groups validated digits with their parsed form.
    public init(digits: String, number: CardAccessNumber) {
      self.digits = digits
      self.number = number
    }
  }

  /// The active offer the driver reads: what the holder just typed, or
  /// the stored number the app selected for the card on the reader.
  internal static let offerAccount = "refineid-offer-can"

  /// Per-card library entries live under this prefix and suffix, with
  /// the card's printed serial between them.
  internal static let libraryPrefix = "refineid-card-"
  internal static let librarySuffix = "-can"

  /// The marker the driver leaves when the card refused the offer.
  internal static let refusalAccount = "refineid-offer-refused"

  /// How many stored numbers one unseal tries at most.
  internal static let maximumCandidates = 5

  /// Offers `digits` as the active number, replacing any previous one.
  @discardableResult
  internal static func publish(digits: String) -> Bool {
    guard CardAccessNumber(digits: digits) != nil else { return false }
    clearRefusal()
    return CardCredentialStore.writeShared(digits, account: offerAccount) == errSecSuccess
  }

  /// The active offer, or nil when nothing is offered.
  internal static func offeredDigits() -> String? {
    CardCredentialStore.readShared(account: offerAccount)
  }

  /// Withdraws the offer, marker included.
  public static func withdraw() {
    clearRefusal()
    CardCredentialStore.deleteShared(account: offerAccount)
    // Migration: builds before the data-protection opt-in wrote these
    // ungrouped, where no grouped query can see them.
    CardCredentialStore.delete(account: offerAccount)
    CardCredentialStore.delete(account: refusalAccount)
  }

  /// Records that the card refused the offer.
  internal static func recordRefusal() {
    _ = CardCredentialStore.writeShared("", account: refusalAccount)
  }

  /// Whether the offer stands refused by the card.
  internal static func refusalRecorded() -> Bool {
    CardCredentialStore.existsShared(account: refusalAccount)
  }

  /// Clears the refusal, for an offer that succeeded after all.
  internal static func clearRefusal() {
    CardCredentialStore.deleteShared(account: refusalAccount)
  }

  /// Forgets the stored number for the card with this printed serial.
  public static func forget(printedSerial: String) {
    CardCredentialStore.deleteShared(account: libraryAccount(printedSerial: printedSerial))
  }

  /// The printed serials with a stored number, in stable account order.
  ///
  /// Serials are printed on the card and safe to display; digits never
  /// leave the keychain through this call.
  public static func storedSerials() -> [String] {
    libraryAccounts().compactMap { account in
      guard
        account.hasPrefix(libraryPrefix),
        account.hasSuffix(librarySuffix)
      else { return nil }
      let serial = account.dropFirst(libraryPrefix.count).dropLast(librarySuffix.count)
      return serial.isEmpty ? nil : String(serial)
    }
  }

  /// Remembers `digits` for the card with this printed serial.
  internal static func remember(digits: String, printedSerial: String) {
    guard CardAccessNumber(digits: digits) != nil else { return }
    _ = CardCredentialStore.writeShared(
      digits, account: libraryAccount(printedSerial: printedSerial))
  }

  /// The library account for one printed serial.
  internal static func libraryAccount(printedSerial: String) -> String {
    libraryPrefix + printedSerial.lowercased() + librarySuffix
  }

  /// Every stored number to try, active offer first.
  ///
  /// Deduplicated and bounded: a household of cards mints within a few
  /// attempts, and a wrong number costs only the time its PACE takes.
  internal static func candidates() -> [Candidate] {
    var seen = Set<String>()
    var selected: [Candidate] = []
    let offered = [offeredDigits()].compactMap(\.self) + libraryDigits()
    for digits in offered {
      guard !seen.contains(digits), let number = CardAccessNumber(digits: digits) else {
        continue
      }
      seen.insert(digits)
      selected.append(Candidate(digits: digits, number: number))
      if selected.count == maximumCandidates { break }
    }
    return selected
  }

  /// The library numbers, in stable account order.
  internal static func libraryDigits() -> [String] {
    libraryAccounts().compactMap { account in
      CardCredentialStore.readShared(account: account)
    }
  }

  /// The library accounts holding stored numbers.
  internal static func libraryAccounts() -> [String] {
    if TestCredentialEnvironment.isTestMode {
      return TestCredentialEnvironment.credentialAccounts(
        prefix: libraryPrefix, suffix: librarySuffix)
    }
    var query = CardCredentialStore.query(
      account: offerAccount, accessGroup: CardCredentialStore.sharedKeychainGroup)
    query.removeValue(forKey: kSecAttrAccount as String)
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    query[kSecReturnAttributes as String] = true
    var items: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
      let found = items as? [[String: Any]]
    else {
      return []
    }
    return found.compactMap { $0[kSecAttrAccount as String] as? String }
      .filter { $0.hasPrefix(libraryPrefix) && $0.hasSuffix(librarySuffix) }
      .sorted()
  }

  /// Where a read that found nothing actually failed: each step of the
  /// path, never any digits.
  ///
  /// For the driver's log. The app and the driver resolve the group
  /// independently, and a miss on one side of a number the other side
  /// wrote can only be told apart by asking the failing process itself.
  public static func missDescription() -> String {
    let group = CardCredentialStore.sharedKeychainGroup ?? "default"
    let offered = offeredDigits() != nil
    return "group=\(group) offered=\(offered) library=\(libraryAccounts().count)"
  }
}
