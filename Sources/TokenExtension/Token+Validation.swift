// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@_spi(TokenExtension) import CardCore
// swiftlint:disable:previous attributes
import CryptoTokenKit
import Foundation
import Security

/// Certificate and stored-prime validation performed before token publication.
extension Token {
  /// A resolved qualified-signature identity: leaf, profile, key.
  internal struct QualifiedMaterial {
    /// Parsed qualified-signature certificate.
    internal let leaf: SecCertificate

    /// The qualified key's resolved profile.
    internal let profile: CardKeyProfile

    /// The qualified leaf's public key.
    internal let publicKey: SecKey
  }

  /// Reads and validates everything needed for one reader-backed token.
  internal static func validatedReaderMaterial(
    from smartCard: TKSmartCard
  ) throws -> ReaderTokenMaterial {
    TokenLog.info("Token.init: reading identity")
    let (identity, accessNumber) = try Self.readIdentity(from: smartCard)
    TokenLog.info(
      "Token.init: leaf=\(identity.leafDER.count) issuer=\(identity.issuerDER?.count ?? -1)"
    )
    guard let leaf = SecCertificateCreateWithData(nil, identity.leafDER as CFData) else {
      TokenLog.error("Token.init: SecCertificateCreateWithData(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    let (profile, publicKey) = try Self.validatedSigningKey(in: leaf)
    guard let instanceID = TokenInstanceID(chipSerial: identity.chipSerial) else {
      TokenLog.error("Token.init: chip serial has no supported printed form")
      throw TokenError.unsupportedKeyProfile
    }
    let sign = Self.validatedQualifiedMaterial(fromDER: identity.signLeafDER)
    return ReaderTokenMaterial(
      identity: identity,
      accessNumber: accessNumber,
      leaf: leaf,
      profile: profile,
      publicKey: publicKey,
      signLeaf: sign?.leaf,
      signProfile: sign?.profile,
      signPublicKey: sign?.publicKey,
      instanceID: instanceID
    )
  }

  /// Resolves the qualified-signature leaf, best effort: a card whose
  /// sign slot is absent or unsupported still publishes its
  /// authentication identity, just without a qualified key.
  private static func validatedQualifiedMaterial(
    fromDER der: Data?
  ) -> QualifiedMaterial? {
    guard
      let der,
      let leaf = SecCertificateCreateWithData(nil, der as CFData),
      let (profile, publicKey) = try? Self.validatedSigningKey(in: leaf)
    else {
      return nil
    }
    return QualifiedMaterial(leaf: leaf, profile: profile, publicKey: publicKey)
  }

  /// Validates every piece of a stored contactless identity.
  internal static func validated(
    primed: PrimedIdentity,
    chipSerial: ChipSerial
  ) throws -> PrimedTokenMaterial {
    guard let accessNumber = CardAccessNumber(digits: primed.can) else {
      TokenLog.trace("Token.init(primed): stored card access number is not usable")
      throw TokenError.primeMissing
    }
    guard let leaf = SecCertificateCreateWithData(nil, primed.certDER as CFData) else {
      TokenLog.trace("Token.init(primed): stored leaf \(primed.certDER.count)B is not a cert")
      throw TokenError.certificateUnreadable
    }
    let (profile, publicKey) = try Self.validatedSigningKey(in: leaf)
    guard primed.chipSerial == chipSerial else {
      TokenLog.trace("Token.init(primed): stored serial is not this card's")
      throw TokenError.primeMissing
    }
    return PrimedTokenMaterial(
      accessNumber: accessNumber,
      leaf: leaf,
      profile: profile,
      publicKey: publicKey,
      serial: chipSerial
    )
  }

  /// Resolves a leaf to one signing profile and its public key.
  private static func validatedSigningKey(
    in leaf: SecCertificate
  ) throws -> (profile: CardKeyProfile, publicKey: SecKey) {
    guard let profile = CardKeyProfile.resolve(fromCertificate: leaf) else {
      TokenLog.error("Token.init: unsupported key profile")
      throw TokenError.unsupportedKeyProfile
    }
    guard SigningAlgorithmResolver.supportsSigning(profile) else {
      TokenLog.error("Token.init: \(profile) has no supported signing shape")
      throw TokenError.unsupportedKeyProfile
    }
    guard let publicKey = SecCertificateCopyKey(leaf) else {
      TokenLog.error("Token.init: SecCertificateCopyKey(leaf) nil")
      throw TokenError.certificateUnreadable
    }
    return (profile, publicKey)
  }
}
