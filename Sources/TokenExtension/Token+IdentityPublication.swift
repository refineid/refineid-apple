// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation
import Security

/// Publishes one token's signed identity to Safari.
extension Token {
  /// Label naming the PIN1 authentication identity.
  ///
  /// Both card certificates carry the identical subject, so a chooser
  /// showing only subjects shows two rows that read the same. The label
  /// is the one publishable field that can tell them apart, and Safari's
  /// chooser appends the subject to it on its own - so the label holds
  /// nothing but the role, in DVV's wording for the PIN it will ask for,
  /// resolved against the system language when the token is minted.
  private static var authenticationLabel: String {
    String(localized: "Basic (PIN 1)")
  }

  /// Builds the keychain items published for browser authentication.
  ///
  /// Only the authentication key and certificate (PIN 1) are published to
  /// the system keychain. Qualified signing keys (PIN 2) are not published
  /// as client authentication identities for websites.
  internal static func makePublicationKeychainItems(
    leaf: SecCertificate,
    profile: CardKeyProfile,
    interface: CardInterface,
    issuerDER: Data?
  ) throws -> [TKTokenKeychainItem] {
    let hasStoredPin = CardCredentialStore.contents().hasPin1
    let requiresPin =
      interface != .fieldWithDeadline || (OnDemandPinExperiment.isEnabled && !hasStoredPin)
    let items = CardTokenPublicationItems.makeItems(
      leaf: leaf,
      profile: profile,
      issuerDER: issuerDER,
      requiresPinConstraint: requiresPin
    )
    guard !items.isEmpty else {
      TokenLog.error("publish: keychain item construction failed")
      throw TokenError.keychainItemConstructionFailed
    }
    return items
  }

  /// Builds and fills the keychain contents from the read identity.
  internal func publish(
    _ identity: PublishedIdentity,
    leaf: SecCertificate,
    profile: CardKeyProfile,
    signLeaf: SecCertificate?,
    signProfile: CardKeyProfile?
  ) throws {
    _ = signLeaf
    _ = signProfile
    let items = try Self.makePublicationKeychainItems(
      leaf: leaf,
      profile: profile,
      interface: interface,
      issuerDER: identity.issuerDER
    )
    TokenLog.info(
      "publish: filling \(items.count) items, keychainContents=\(keychainContents != nil) "
        + "publicKeyData=\(items.compactMap { ($0 as? TKTokenKeychainKey)?.publicKeyData }.first?.count ?? -1)B"
    )
    keychainContents?.fill(with: items)
  }
}
