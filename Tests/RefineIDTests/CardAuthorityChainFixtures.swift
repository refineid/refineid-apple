// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation

/// A generated three-level card chain: a self-signed root, an issuing CA
/// it signed, and an authentication leaf the issuing CA signed, plus an
/// expired root with the same name and key.
internal enum CardAuthorityChainFixtures {
  /// One generated chain.
  internal struct Chain: Sendable {
    /// The self-signed root, valid now.
    internal let root: Data

    /// The same root name and key, its validity already ended.
    internal let expiredRoot: Data

    /// A self-signed CA with the root's name and a different key.
    internal let impostorRoot: Data

    /// The issuing CA the root signed.
    internal let issuing: Data

    /// The end-entity certificate the issuing CA signed.
    internal let leaf: Data
  }

  /// Fields that vary across the generated certificates.
  private struct Description {
    let subject: Data
    let issuer: Data
    let serial: Data
    let notAfter: String
    let publicKey: P256.Signing.PrivateKey
    let signer: P256.Signing.PrivateKey
    let certificateAuthority: Bool
  }

  /// ASN.1 BOOLEAN.
  private static let tagBoolean: UInt8 = 0x01

  /// ASN.1 BIT STRING.
  private static let tagBitString: UInt8 = 0x03

  /// ASN.1 UTF8String.
  private static let tagUtf8String: UInt8 = 0x0C

  /// ASN.1 GeneralizedTime.
  private static let tagGeneralizedTime: UInt8 = 0x18

  /// ASN.1 explicit context tag `[0]`.
  private static let tagContext0Constructed: UInt8 = 0xA0

  /// ASN.1 explicit context tag `[3]`.
  private static let tagContext3Constructed: UInt8 = 0xA3

  /// DER BOOLEAN TRUE content.
  private static let booleanTrue: UInt8 = 0xFF

  /// id-at-commonName.
  private static let commonNameOid = "2.5.4.3"

  /// id-ecPublicKey.
  private static let ecPublicKeyOid = "1.2.840.10045.2.1"

  /// prime256v1.
  private static let p256CurveOid = "1.2.840.10045.3.1.7"

  /// ecdsa-with-SHA256.
  private static let ecdsaSha256Oid = "1.2.840.10045.4.3.2"

  /// id-ce-basicConstraints.
  private static let basicConstraintsOid = "2.5.29.19"

  /// id-ce-keyUsage.
  private static let keyUsageOid = "2.5.29.15"

  /// X.509 version value for version 3 certificates.
  private static let certificateVersionThree = 2

  /// One unused bit after keyCertSign and cRLSign.
  private static let oneUnusedBit: UInt8 = 1

  /// DER KeyUsage payload containing keyCertSign and cRLSign.
  private static let keyCertAndCrlSignBits: UInt8 = 6

  /// Seven unused bits after digitalSignature.
  private static let sevenUnusedBits: UInt8 = 7

  /// DER KeyUsage payload containing digitalSignature.
  private static let digitalSignatureBit: UInt8 = 128

  /// Validity start shared by every generated certificate.
  private static let notBefore = "20250101000000Z"

  /// Validity end of a certificate that is still valid.
  private static let validNotAfter = "20300101000000Z"

  /// Validity end of a certificate that has already expired.
  private static let expiredNotAfter = "20260101000000Z"

  /// Serials of the generated certificates.
  private static let rootSerial = Data("1".utf8)
  private static let expiredRootSerial = Data("2".utf8)
  private static let impostorSerial = Data("3".utf8)
  private static let issuingSerial = Data("4".utf8)
  private static let leafSerial = Data("5".utf8)

  /// Generates one chain with fresh keys.
  internal static func make() throws -> Chain {
    let rootKey = P256.Signing.PrivateKey()
    let impostorKey = P256.Signing.PrivateKey()
    let issuingKey = P256.Signing.PrivateKey()
    let leafKey = P256.Signing.PrivateKey()
    let rootName = Self.name("RefineID Test Root CA")
    let issuingName = Self.name("RefineID Test Issuing CA")
    let root = try Self.certificate(
      Description(
        subject: rootName, issuer: rootName, serial: Self.rootSerial,
        notAfter: Self.validNotAfter, publicKey: rootKey, signer: rootKey,
        certificateAuthority: true))
    let expiredRoot = try Self.certificate(
      Description(
        subject: rootName, issuer: rootName, serial: Self.expiredRootSerial,
        notAfter: Self.expiredNotAfter, publicKey: rootKey, signer: rootKey,
        certificateAuthority: true))
    let impostorRoot = try Self.certificate(
      Description(
        subject: rootName, issuer: rootName, serial: Self.impostorSerial,
        notAfter: Self.validNotAfter, publicKey: impostorKey, signer: impostorKey,
        certificateAuthority: true))
    let issuing = try Self.certificate(
      Description(
        subject: issuingName, issuer: rootName, serial: Self.issuingSerial,
        notAfter: Self.validNotAfter, publicKey: issuingKey, signer: rootKey,
        certificateAuthority: true))
    let leaf = try Self.certificate(
      Description(
        subject: Self.name("RefineID Test Holder"), issuer: issuingName,
        serial: Self.leafSerial, notAfter: Self.validNotAfter, publicKey: leafKey,
        signer: issuingKey, certificateAuthority: false))
    return Chain(
      root: root,
      expiredRoot: expiredRoot,
      impostorRoot: impostorRoot,
      issuing: issuing,
      leaf: leaf)
  }

  /// Constructs one v3 certificate and signs its exact TBSCertificate.
  private static func certificate(_ description: Description) throws -> Data {
    let algorithm = DerEncoder.sequence([DerEncoder.objectIdentifier(Self.ecdsaSha256Oid)])
    let tbs = DerEncoder.sequence([
      DerEncoder.tlv(
        Self.tagContext0Constructed, DerEncoder.integer(Self.certificateVersionThree)),
      DerEncoder.unsignedInteger(description.serial),
      algorithm,
      description.issuer,
      DerEncoder.sequence([
        Self.generalizedTime(Self.notBefore),
        Self.generalizedTime(description.notAfter),
      ]),
      description.subject,
      Self.subjectPublicKeyInfo(description.publicKey),
      DerEncoder.tlv(
        Self.tagContext3Constructed,
        Self.extensions(certificateAuthority: description.certificateAuthority)),
    ])
    let signature = try description.signer.signature(for: tbs).derRepresentation
    return DerEncoder.sequence([tbs, algorithm, Self.bitString(signature)])
  }

  /// BasicConstraints and KeyUsage for a CA or an end entity.
  private static func extensions(certificateAuthority: Bool) -> Data {
    let constraints =
      certificateAuthority
      ? DerEncoder.sequence([Self.boolean(true)])
      : DerEncoder.sequence([])
    let usage =
      certificateAuthority
      ? Data([Self.oneUnusedBit, Self.keyCertAndCrlSignBits])
      : Data([Self.sevenUnusedBits, Self.digitalSignatureBit])
    return DerEncoder.sequence([
      Self.extensionValue(oid: Self.basicConstraintsOid, value: constraints),
      Self.extensionValue(
        oid: Self.keyUsageOid, value: DerEncoder.tlv(Self.tagBitString, usage)),
    ])
  }

  /// One critical X.509 Extension.
  private static func extensionValue(oid: String, value: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(oid),
      Self.boolean(true),
      DerEncoder.octetString(value),
    ])
  }

  /// SubjectPublicKeyInfo for a P-256 key.
  private static func subjectPublicKeyInfo(_ key: P256.Signing.PrivateKey) -> Data {
    DerEncoder.sequence([
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.ecPublicKeyOid),
        DerEncoder.objectIdentifier(Self.p256CurveOid),
      ]),
      Self.bitString(key.publicKey.x963Representation),
    ])
  }

  /// A distinguished Name with one commonName attribute.
  private static func name(_ commonName: String) -> Data {
    let attribute = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.commonNameOid),
      DerEncoder.tlv(Self.tagUtf8String, Data(commonName.utf8)),
    ])
    return DerEncoder.sequence([DerEncoder.setOf([attribute])])
  }

  /// DER BOOLEAN.
  private static func boolean(_ value: Bool) -> Data {
    DerEncoder.tlv(Self.tagBoolean, Data([value ? Self.booleanTrue : 0]))
  }

  /// DER GeneralizedTime from fixed test text.
  private static func generalizedTime(_ value: String) -> Data {
    DerEncoder.tlv(Self.tagGeneralizedTime, Data(value.utf8))
  }

  /// DER BIT STRING with no unused trailing bits.
  private static func bitString(_ value: Data) -> Data {
    DerEncoder.tlv(Self.tagBitString, Data([0]) + value)
  }
}
