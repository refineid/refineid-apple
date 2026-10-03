// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Where a primed identity waits between the app that read it and the
/// token extension that needs it.
///
/// The two are separate processes, and `ctkd` purges the app-side
/// `TKTokenDriver.Configuration` entries for a smart-card driver class the
/// moment the driver creates a token -- so the obvious channel deletes
/// itself exactly when it would be used. A keychain item in the shared
/// access group is the one store both sides genuinely share, and it is
/// where a card access number belongs anyway.
///
/// Items are `WhenUnlockedThisDeviceOnly` and non-synchronizable: a prime
/// is only ever read while the holder is standing over an unlocked device
/// driving a login, so nothing here needs to survive a lock, a backup, or
/// a restore onto another device. Neither attribute implies the other;
/// both are set. `kSecUseDataProtectionKeychain` must be set identically
/// on both sides or the app and the extension address different keychains
/// and silently never see each other's writes.
///
/// Nothing in this type logs. The value it carries includes a card access
/// number, and a store that narrates its work is a store that eventually
/// narrates that.
///
/// Provenance: the reader `PrimeStore` in the donor
/// `platform/apple/RefineIDTokenExtension/PrimeStore.swift` and the writer
/// `SafariIdentityPrime.storePrimedIdentity` in
/// `platform/apple/RefineID/Local/SafariIdentityPrime+PrimeStore.swift`.
public enum PrimeStore {
  /// One decoded keychain record, still named only inside this store.
  internal struct StoredItem {
    internal let account: String
    internal let identity: PrimedIdentity
  }

  /// The dated marker naming the app's own registration field.
  private struct RegistrationFieldMark: Codable {
    let markedAt: Date
  }

  /// Keychain service the primed identities live under.
  internal static let service: String = "fi.refineid.prime"

  /// Short-lived bridge record earlier builds staged between two fields.
  ///
  /// No longer written; still deleted so a leftover from an earlier
  /// build cannot linger in the shared group.
  private static let stagedAccount = "staged-contactless-card"

  /// Names the app's registration hold for the extension's mint.
  private static let registrationMarkAccount = "registration-field-mark"

  /// A mark exists only to bridge one registration hold.
  private static let maximumMarkAge: TimeInterval = 90

  /// Tolerates a small wall-clock adjustment between app and extension.
  private static let allowedFutureSkew: TimeInterval = 5

  /// Stores the primed identity for one card, replacing any previous one.
  ///
  /// Returns false when the keychain refuses the write, so a caller can
  /// tell the holder that priming did not stick rather than leaving them
  /// to discover it at the next login.
  @discardableResult
  public static func store(
    _ identity: PrimedIdentity,
    forLookup lookupID: PrimeLookupIdentifier
  ) -> Bool {
    guard let payload = try? JSONEncoder().encode(identity) else { return false }
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.storePrime(payload, account: lookupID.value)
      return true
    }
    let coordinates = query(account: lookupID.value)
    let replacement = [kSecValueData as String: payload]
    let updated = SecItemUpdate(coordinates as CFDictionary, replacement as CFDictionary)
    if updated == errSecSuccess { return true }
    guard updated == errSecItemNotFound else { return false }

    var insertion = coordinates
    insertion[kSecValueData as String] = payload
    if KeychainPlatform.usesDataProtection {
      insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    let addStatus = SecItemAdd(insertion as CFDictionary, nil)
    if addStatus == errSecSuccess { return true }
    if addStatus == errSecDuplicateItem {
      return SecItemUpdate(coordinates as CFDictionary, replacement as CFDictionary)
        == errSecSuccess
    }
    return false
  }

  /// Marks the next NFC field as the app's own registration hold.
  ///
  /// Written BEFORE the app opens its slot: `ctkd` asks the extension
  /// for a token the moment the card arrives, so anything written after
  /// that races the mint. While the mark is fresh the extension
  /// publishes metadata without taking a card session, leaving the card
  /// to the app for PACE, the reads, and `registerSmartCard`.
  @discardableResult
  public static func markRegistrationField() -> Bool {
    guard
      let payload = try? JSONEncoder().encode(RegistrationFieldMark(markedAt: Date()))
    else {
      return false
    }
    var attributes = query(account: Self.registrationMarkAccount)
    attributes[kSecValueData as String] = payload
    if KeychainPlatform.usesDataProtection {
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    delete(account: Self.registrationMarkAccount)
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  /// Removes the registration mark when the hold ends, however it ends.
  public static func clearRegistrationField() {
    delete(account: Self.registrationMarkAccount)
  }

  /// Whether the app's registration hold is running right now.
  ///
  /// Bounded by age rather than trusted forever: the app clears the mark
  /// when its hold ends, and the age limit covers a run that never got
  /// to. A stale mark would make a signing field publish without a card
  /// session, which fails the signature that follows.
  private static func registrationFieldMarked() -> Bool {
    var query = self.query(account: Self.registrationMarkAccount)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let mark = try? JSONDecoder().decode(RegistrationFieldMark.self, from: data)
    else {
      return false
    }
    let age = Date().timeIntervalSince(mark.markedAt)
    return age >= -Self.allowedFutureSkew && age <= Self.maximumMarkAge
  }

  /// The primed identity for one card, or nil when there is none.
  ///
  /// A stored record is re-validated through `PrimedIdentity`'s own
  /// initializer instead of being trusted: decoding proves the bytes are
  /// well-formed JSON, not that they still describe a usable prime.
  public static func read(lookupID: PrimeLookupIdentifier) -> PrimedIdentity? {
    read(account: lookupID.value)
  }

  /// The exact ATR record, marked with the purpose of the live field.
  ///
  /// The registration mark must win even when the record predates the
  /// hold. Otherwise a re-prime looks like a signing field, and the
  /// extension starts PACE while the app is trying to register the
  /// token.
  public static func readContactless(
    lookupID: PrimeLookupIdentifier
  ) -> ContactlessMatch? {
    guard let exact = read(lookupID: lookupID) else { return nil }
    return ContactlessMatch(
      identity: exact,
      isRegistrationField: registrationFieldMarked())
  }

  /// Decodes and validates one record by keychain account.
  internal static func read(account: String) -> PrimedIdentity? {
    if TestCredentialEnvironment.isTestMode {
      guard let data = TestCredentialEnvironment.readPrime(account: account),
        let stored = try? JSONDecoder().decode(PrimedIdentity.self, from: data)
      else {
        return nil
      }
      return PrimedIdentity(
        can: stored.can,
        certificate: stored.certDER,
        issuer: stored.issuerDER,
        tokenSerial: stored.tokenSerial,
        activationCheck: stored.activationCheck,
        contactlessIdentification: stored.contactlessIdentification,
        stagedAt: stored.stagedAt,
        signatureCertificate: stored.signatureCertDER)
    }
    var query = self.query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let stored = try? JSONDecoder().decode(PrimedIdentity.self, from: data)
    else {
      return nil
    }
    return PrimedIdentity(
      can: stored.can,
      certificate: stored.certDER,
      issuer: stored.issuerDER,
      tokenSerial: stored.tokenSerial,
      activationCheck: stored.activationCheck,
      contactlessIdentification: stored.contactlessIdentification,
      stagedAt: stored.stagedAt,
      signatureCertificate: stored.signatureCertDER)
  }

  /// Removes the primed identity for one card.
  public static func forget(lookupID: PrimeLookupIdentifier) {
    delete(account: lookupID.value)
  }

  /// Whether a stored prime belongs to this physical card.
  ///
  /// The lookup key is derived from an ATR and therefore names a card
  /// family, not a physical card. Revocation starts with the public card
  /// serial instead, so it cannot remove another card's prime merely
  /// because both cards expose the same ATR.
  public static func contains(instanceID: CardInstanceIdentifier) -> Bool {
    storedItems().contains { item in
      guard
        let serialText = item.identity.tokenSerial,
        let serial = TokenSerial(value: serialText)
      else {
        return false
      }
      return CardInstanceIdentifier(tokenSerial: serial) == instanceID
    }
  }

  /// Removes every exact or staged prime belonging to one physical card.
  ///
  /// A physical card can acquire more than one ATR lookup record across
  /// interfaces or card generations. The printed-card instance identifier
  /// is the stable revocation boundary, so all matching records go together.
  public static func forget(instanceID: CardInstanceIdentifier) {
    for item in storedItems() {
      guard
        let serialText = item.identity.tokenSerial,
        let serial = TokenSerial(value: serialText),
        CardInstanceIdentifier(tokenSerial: serial) == instanceID
      else {
        continue
      }
      delete(account: item.account)
    }
  }

  /// Removes every short-lived bridge record.
  ///
  /// The staged account is an earlier build's bridge; deleting it here
  /// keeps a leftover from ever serving a mint again.
  public static func forgetStaged() {
    delete(account: Self.stagedAccount)
    delete(account: Self.registrationMarkAccount)
  }

  /// Removes every primed identity this device holds.
  ///
  /// The holder revoking their consent to a stored card access number
  /// must be able to revoke it for all their cards at once, without
  /// having to present each card again to name it.
  public static func forgetAll() {
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.forgetAllPrimes()
      return
    }
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if KeychainPlatform.usesDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
      query[kSecAttrSynchronizable as String] = false
    }
    SecItemDelete(query as CFDictionary)
  }

  /// How many cards this device currently holds a prime for.
  ///
  /// A count and nothing else. The record names one card and carries its
  /// card access number, so a caller that only needs to know whether
  /// priming stuck gets a number rather than something to leak. Zero is
  /// also the answer when the keychain refuses the search, which reads the
  /// same way to a caller: there is no prime here to serve a login with.
  public static func storedCount() -> Int {
    presence().count
  }

  /// What this device holds for each primed card, presence only.
  ///
  /// ``storedCount()`` answers whether priming stuck at all; this answers
  /// which part of it stuck, which is the difference between a card that
  /// was never read and one whose issuer certificate never arrived. The
  /// records are decoded here, inside the type that owns them, and only
  /// presence and sizes leave: no card access number, no certificate
  /// bytes, no serial. An unreadable or undecodable record is skipped
  /// rather than reported as an empty one, because a prime that cannot be
  /// decoded is a prime the extension will not see either.
  public static func presence() -> [PrimePresence] {
    presenceOrderedItems()
      .map { item in
        PrimePresence(
          instance: item.account,
          hasCardAccessNumber: !item.identity.can.isEmpty,
          certificateBytes: item.identity.certDER.count,
          issuerBytes: item.identity.issuerDER?.count ?? 0,
          hasTokenSerial: item.identity.tokenSerial != nil)
      }
  }

  /// The holder each primed card names, in the order ``presence()``
  /// lists them.
  ///
  /// Only the name leaves, decoded here for the reason ``presence()``
  /// decodes here: the certificate bytes, the card access number and
  /// the serial belong to this type. The name is the one part of a
  /// prime a window has to show, and reading it from the record asks
  /// no card at all - the alternative, searching the keychain for what
  /// the token published, has to mint a registered card to answer, and
  /// minting one over near field opens a scan sheet.
  ///
  /// A record whose certificate will not parse is skipped rather than
  /// reported as an empty name, exactly as an undecodable record is.
  public static func primedHolderNames() -> [String] {
    presenceOrderedItems().compactMap { item in
      if let formatted = DistinguishedName.holderLine(fromCertificate: item.identity.certDER) {
        return formatted
      }
      guard
        let certificate = SecCertificateCreateWithData(
          nil, item.identity.certDER as CFData),
        let summary = SecCertificateCopySubjectSummary(certificate) as String?
      else {
        return nil
      }
      return summary
    }
  }

  /// The holder identifiers (SATU / PEUIN) each primed card names.
  public static func primedIdentifiers() -> [String] {
    presenceOrderedItems().compactMap { item in
      DistinguishedName.identifier(fromCertificate: item.identity.certDER)
    }
  }

  /// The authentication certificates this device has already primed.
  ///
  /// The certificate is public and was read once, during setup, so a peer
  /// asking for it is asking for something already held. Answering from
  /// here spends no card session and asks the holder for nothing.
  public static func primedAuthenticationCertificates() -> [Data] {
    presenceOrderedItems().map(\.identity.certDER)
  }

  /// The stored primed identities this device holds.
  public static func storedIdentities() -> [PrimedIdentity] {
    let identities = presenceOrderedItems().map(\.identity)
    for identity in identities {
      if let issuer = identity.issuerDER {
        TrustRootsCache.shared.register(issuer)
      }
    }
    return identities
  }

  /// The authentication certificates this device has already primed.
  ///
  /// Read from the stored prime records rather than asking the keychain
  /// for certificates: the tokens for registered cards are not minted
  /// while the card is away, so the keychain holds no identity items
  /// for them, and minting them over near field opens a scan sheet.
  ///
  /// The issuer certificate travels with each prime because the extension
  /// has no network access to resolve `caIssuers` at runtime, so it must
  /// be available locally for certificate path validation.
  public static func primedCertificates() -> [(certificate: Data, issuer: Data?)] {
    presenceOrderedItems().map { (certificate: $0.identity.certDER, issuer: $0.identity.issuerDER) }
  }

  /// Every primed card in the order ``presence()`` reports it.
  ///
  /// The short-lived staged record is left out: it is an in-flight
  /// hold, not a card this device keeps.
  private static func presenceOrderedItems() -> [StoredItem] {
    storedItems()
      .filter { $0.account != Self.stagedAccount }
      .sorted { $0.account < $1.account }
  }
}
