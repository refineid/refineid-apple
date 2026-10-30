// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Where this device keeps the card access number.
///
/// The card access number is the holder's to see -- it is printed on the
/// card face -- and ``displayedCardAccessNumber()`` returns it for the
/// manager window. It never enters a log. No PIN is ever stored: PIN 1 is
/// held only in the memory of the process that asked for it, and PIN 2 is
/// asked for every signature (RAPP v26.10.29 §11 item 2).
///
/// The item is `WhenUnlockedThisDeviceOnly` and non-synchronizable, so it
/// is never written into a backup, restored onto another device, or sent
/// to iCloud. Neither attribute implies the other; both are set. It
/// carries no `SecAccessControl`: the token extension reads it while
/// opening the card for a Safari request and has no interface to answer a
/// prompt.
public enum CardCredentialStore {
  // MARK: Nested Types

  /// What the store currently holds.
  public struct Contents: Equatable, Sendable {
    // MARK: Properties

    /// Whether a card access number is stored.
    public let hasCardAccessNumber: Bool

    // MARK: Lifecycle

    /// Records what a store lookup found.
    public init(hasCardAccessNumber: Bool) {
      self.hasCardAccessNumber = hasCardAccessNumber
    }
  }

  // MARK: Static Properties

  /// Posted in-process whenever the stored CAN is explicitly removed.
  ///
  /// The app uses this to clear any visible copy immediately after the
  /// card rejects PACE. It is deliberately an event rather than polling.
  public static let cardAccessNumberDidInvalidate =
    Notification.Name("fi.refineid.card-access-number-did-invalidate")

  /// Keychain service the card credentials live under.
  internal static let service = "fi.refineid.credentials"

  /// Account for the card access number.
  internal static let cardAccessNumberAccount = "can"

  // MARK: Static Functions

  /// What is stored, without reading any secret.
  public static func contents() -> Contents {
    Contents(hasCardAccessNumber: exists(account: cardAccessNumberAccount))
  }

  /// Stores the card access number, replacing any previous one.
  ///
  /// Also hands it to the token driver, which on macOS cannot read the
  /// keychain item this just wrote. See `publishCardAccessNumberToDriver`.
  @discardableResult
  public static func save(cardAccessNumber digits: String) -> OSStatus {
    guard CardAccessNumber(digits: digits) != nil else { return errSecParam }
    let status = write(digits, account: cardAccessNumberAccount)
    if status == errSecSuccess {
      publishToDriver(digits: digits)
    }
    return status
  }

  /// An opaque name for the stored number: equal when the number is,
  /// never convertible back to digits.
  ///
  /// Lets the token driver remember "this exact number was refused by
  /// this card" across offers without holding digits, which is what
  /// stops a wrong number from being retried against the card for as
  /// long as it rests on the antenna.
  public static func cardAccessNumberFingerprint() -> Data? {
    var digits = read(account: cardAccessNumberAccount).map { Data($0.utf8) }
    #if os(macOS)
      if digits == nil {
        digits = CardCanOffer.offeredDigits().map { Data($0.utf8) }
      }
    #endif
    guard let digits else { return nil }
    return Data(SHA256.hash(data: digits))
  }

  /// The opaque fingerprint of one number, for refusal latching.
  ///
  /// Never convertible back to digits, which is what stops a wrong
  /// number from being retried against the card for as long as it
  /// rests on the antenna.
  public static func fingerprint(canDigits: String) -> Data {
    Data(SHA256.hash(data: Data(canDigits.utf8)))
  }

  /// Hands the stored card access number to the token driver, for the
  /// platform where it cannot read the keychain item itself.
  ///
  /// Called by the app when it starts, not only when the number is
  /// entered: a number stored before this channel existed, or by a
  /// previous version, would otherwise stay invisible to the driver
  /// until the holder happened to type it again.
  ///
  /// Answers whether anything was published, so a caller can say so.
  /// False covers both nothing stored and a process that is not the
  /// driver's hosting application, neither of which is an error.
  @discardableResult
  public static func publishCardAccessNumberToDriver() -> Bool {
    guard let digits = read(account: cardAccessNumberAccount) else { return false }
    return publishToDriver(digits: digits)
  }

  /// Publishes a just-typed card access number for the driver's next
  /// unseal, keeping it nowhere else.
  ///
  /// This is the macOS route for a sealed contactless card: the holder
  /// types the number where the card appeared, the driver reads it for
  /// the mint, and `withdrawCardAccessNumberFromDriver` takes it back
  /// once the card is published or gone. Nothing is written to the
  /// keychain, so nothing survives to be a previously saved number.
  @discardableResult
  public static func publishCardAccessNumberToDriver(digits: String) -> Bool {
    guard CardAccessNumber(digits: digits) != nil else { return false }
    return publishToDriver(digits: digits)
  }

  /// Withdraws the published number, and the configuration-store
  /// entry earlier versions published, which must not outlive them.
  public static func withdrawCardAccessNumberFromDriver() {
    #if os(macOS)
      CardCanOffer.withdraw()
      DriverConfiguredCredentials.withdraw()
    #endif
  }

  /// Records that the card refused the offered number, where the
  /// window that offered it can see - the token driver has no window
  /// of its own to say so in.
  public static func recordOfferedNumberRefusal() {
    #if os(macOS)
      CardCanOffer.recordRefusal()
    #endif
  }

  /// Whether the offered number stands refused by the card.
  public static func offeredNumberWasRefused() -> Bool {
    #if os(macOS)
      return CardCanOffer.refusalRecorded()
    #else
      return false
    #endif
  }

  /// Clears a recorded refusal, for the offer that succeeded.
  public static func clearOfferedNumberRefusal() {
    #if os(macOS)
      CardCanOffer.clearRefusal()
    #endif
  }

  /// The stored card access number, for the holder to see.
  ///
  /// The number is printed on the card face; hiding it from its holder
  /// protected nothing and cost the manager window its one job. PIN1
  /// has no counterpart to this, and the value still never reaches a
  /// log, a trace or a diagnostics export.
  public static func displayedCardAccessNumber() -> String? {
    read(account: cardAccessNumberAccount)
  }

  /// The stored card access number.
  ///
  /// Reads without prompting: the number is printed on the card, and a
  /// prompt in front of it would cost the holder an interruption on
  /// every card setup for very little.
  public static func cardAccessNumber() -> CardAccessNumber? {
    if let stored = read(account: cardAccessNumberAccount)
      .flatMap(CardAccessNumber.init(digits:))
    {
      return stored
    }
    // The app's offer in the shared keychain group, which on macOS is
    // the only copy the driver can read. Second rather than first, so
    // the keychain stays the source of truth wherever it is readable.
    #if os(macOS)
      return CardCanOffer.offeredDigits().flatMap(CardAccessNumber.init(digits:))
    #else
      return nil
    #endif
  }

  /// The keychain's own answer to "could the card access number be read
  /// from this process?", for when it could not.
  ///
  /// `cardAccessNumber()` answers nil for every reason there is, and the
  /// reasons want different things done about them: `errSecItemNotFound`
  /// is setup that has not happened, while a refusal is one process
  /// being unable to read what another one wrote. A caller that has
  /// already failed can say which it hit instead of guessing.
  /// Asks for the value, not merely the item: on macOS the two are
  /// different questions, because finding an item needs no authorization
  /// while reading its data is what the access control governs. A probe
  /// that omitted the data reported success for an item it could not
  /// actually read.
  public static func cardAccessNumberReadStatus() -> OSStatus {
    #if DEBUG
      if TestCredentialEnvironment.isTestMode {
        return read(account: cardAccessNumberAccount) != nil ? errSecSuccess : errSecItemNotFound
      }
    #endif
    var query = self.query(account: cardAccessNumberAccount)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &item)
  }

  /// The primed identity for a card that was just read, built around the
  /// stored card access number.
  ///
  /// The prime store needs the six digits, and this type is where they
  /// live. Handing them out so a caller could assemble the record itself
  /// would put a card access number in a `String` in the app, in the
  /// extension, and in every caller added later; assembling the record
  /// here means the digits go from the keychain into the prime without
  /// passing through any other file. Returns nil when nothing is stored
  /// or the record would not validate.
  public static func primedIdentity(
    certificate: Data,
    issuer: Data?,
    chipSerial: ChipSerial?,
    activationCheck: PrimedIdentity.ActivationCheck,
    signatureCertificate: Data? = nil
  ) -> PrimedIdentity? {
    guard let digits = read(account: cardAccessNumberAccount) else {
      return nil
    }
    return PrimedIdentity(
      can: digits,
      certificate: certificate,
      issuer: issuer,
      chipSerial: chipSerial,
      activationCheck: activationCheck,
      signatureCertificate: signatureCertificate)
  }

  /// Removes the card access number, from the driver's copy as well.
  public static func forgetCardAccessNumber() {
    delete(account: cardAccessNumberAccount)
    NotificationCenter.default.post(
      name: cardAccessNumberDidInvalidate,
      object: nil)
    #if os(macOS)
      withdrawCardAccessNumberFromDriver()
    #endif
  }

}
