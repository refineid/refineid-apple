// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security

extension CertificateRevocationListFixtures {
  /// ASN.1 BOOLEAN.
  private static let tagBoolean: UInt8 = 0x01

  /// ASN.1 BIT STRING.
  private static let tagBitString: UInt8 = 0x03

  /// ASN.1 NULL.
  private static let tagNull: UInt8 = 0x05

  /// ASN.1 UTF8String.
  private static let tagUtf8String: UInt8 = 0x0C

  /// ASN.1 GeneralizedTime.
  private static let tagGeneralizedTime: UInt8 = 0x18

  /// ASN.1 explicit context tag `[0]`.
  private static let tagContext0Constructed: UInt8 = 0xA0

  /// ASN.1 explicit context tag `[3]`.
  private static let tagContext3Constructed: UInt8 = 0xA3

  /// rsaEncryption.
  private static let rsaEncryptionOid = "1.2.840.113549.1.1.1"

  /// id-ecPublicKey.
  private static let ecPublicKeyOid = "1.2.840.10045.2.1"

  /// id-at-commonName.
  private static let commonNameOid = "2.5.4.3"

  /// id-ce-keyUsage.
  private static let keyUsageOid = "2.5.29.15"

  /// id-ce-basicConstraints.
  private static let basicConstraintsOid = "2.5.29.19"

  /// X.509 version value for version 3 certificates.
  private static let certificateVersionThree = 2

  /// X.509 version value for version 2 CRLs.
  private static let crlVersionTwo = 1

  /// One unused trailing bit in an issuer KeyUsage BIT STRING.
  private static let oneUnusedBit: UInt8 = 1

  /// Two unused trailing bits without cRLSign.
  private static let twoUnusedBits: UInt8 = 2

  /// Seven unused trailing bits in a one-purpose KeyUsage.
  private static let sevenUnusedBits: UInt8 = 7

  /// Payload bits for keyCertSign and cRLSign.
  private static let keyCertAndCrlSignBits: UInt8 = 6

  /// Payload bit for keyCertSign alone.
  private static let keyCertSignBit: UInt8 = 4

  /// Payload bit for digitalSignature alone.
  private static let digitalSignatureBit: UInt8 = 128

  /// DER BIT STRING content denoting keyCertSign and cRLSign.
  private static let issuerKeyUsage = Data([
    Self.oneUnusedBit,
    Self.keyCertAndCrlSignBits,
  ])

  /// DER BIT STRING content denoting digitalSignature.
  private static let targetKeyUsage = Data([
    Self.sevenUnusedBits,
    Self.digitalSignatureBit,
  ])

  /// DER BIT STRING content denoting keyCertSign without cRLSign.
  private static let issuerKeyUsageWithoutCrlSign = Data([
    Self.twoUnusedBits,
    Self.keyCertSignBit,
  ])

  /// cRLSign placed inside bits the BIT STRING declares unused.
  private static let malformedIssuerKeyUsage = Data([
    Self.sevenUnusedBits,
    Self.crlSignKeyUsageBit,
  ])

  /// Payload bit for cRLSign alone.
  private static let crlSignKeyUsageBit: UInt8 = 2

  /// Certificate notBefore.
  private static let certificateNotBefore = "20250101000000Z"

  /// Certificate notAfter.
  private static let certificateNotAfter = "20300101000000Z"

  /// Revocation date placed on generated target entries.
  private static let revocationDate = "20260501000000Z"

  /// Constructs one v3 certificate and signs its exact TBSCertificate.
  internal static func certificate(
    description: CertificateDescription,
    publicKey: SecKey,
    signer: SecKey,
    kind: SignatureKind
  ) throws -> Data {
    let algorithm = Self.algorithmIdentifier(kind)
    let subject = Self.name(description.commonName)
    let extensions = Self.certificateExtensions(
      description: description
    )
    let tbs = DerEncoder.sequence([
      DerEncoder.tlv(
        Self.tagContext0Constructed,
        DerEncoder.integer(Self.certificateVersionThree)
      ),
      DerEncoder.unsignedInteger(description.serial),
      algorithm,
      description.issuerName,
      DerEncoder.sequence([
        Self.generalizedTime(Self.certificateNotBefore),
        Self.generalizedTime(Self.certificateNotAfter),
      ]),
      subject,
      try Self.subjectPublicKeyInfo(publicKey, kind: kind),
      DerEncoder.tlv(Self.tagContext3Constructed, extensions),
    ])
    return DerEncoder.sequence([
      tbs,
      algorithm,
      Self.bitString(try Self.sign(tbs, with: signer, kind: kind)),
    ])
  }

  /// Constructs and signs one v2 CRL.
  internal static func crl(
    issuerKey: SecKey,
    kind: SignatureKind,
    options: Options
  ) throws -> Data {
    let algorithm = Self.algorithmIdentifier(kind)
    var fields = [
      DerEncoder.integer(Self.crlVersionTwo),
      algorithm,
      Self.name(options.crlIssuerCommonName),
      Self.generalizedTime(options.thisUpdate),
    ]
    if options.includesNextUpdate {
      fields.append(Self.generalizedTime(options.nextUpdate))
    }
    if options.listsTargetSerial {
      fields.append(
        Self.revokedCertificates(options.entryExtensions, serial: options.revokedSerial))
    }
    if !options.crlExtensions.isEmpty {
      fields.append(
        DerEncoder.tlv(
          Self.tagContext0Constructed,
          DerEncoder.sequence(options.crlExtensions)
        )
      )
    }
    let tbs = DerEncoder.sequence(fields)
    return DerEncoder.sequence([
      tbs,
      algorithm,
      Self.bitString(try Self.sign(tbs, with: issuerKey, kind: kind)),
    ])
  }

  /// Encodes a distinguished Name containing one commonName attribute.
  internal static func name(_ commonName: String) -> Data {
    let attribute = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.commonNameOid),
      DerEncoder.tlv(Self.tagUtf8String, Data(commonName.utf8)),
    ])
    let relativeName = DerEncoder.setOf([attribute])
    return DerEncoder.sequence([relativeName])
  }

  /// DER BOOLEAN.
  internal static func boolean(_ value: Bool) -> Data {
    let content = value ? Data([Self.booleanTrue]) : Data([0])
    return DerEncoder.tlv(Self.tagBoolean, content)
  }

  /// Standard PEM armor for a CRL.
  internal static func pem(_ der: Data) -> Data {
    let body = der.base64EncodedString(options: .lineLength64Characters)
    return Data(
      ("-----BEGIN X509 CRL-----\n" + body + "\n-----END X509 CRL-----\n").utf8
    )
  }

  /// Certificate extensions needed for a valid direct-issuer trust chain.
  private static func certificateExtensions(
    description: CertificateDescription
  ) -> Data {
    let constraintFields: [Data]
    if description.isCertificateAuthority {
      constraintFields = [Self.boolean(true)]
    } else if description.explicitFalseBasicConstraint {
      constraintFields = [Self.boolean(false)]
    } else {
      constraintFields = []
    }
    let constraints = DerEncoder.sequence(constraintFields)
    let usage: Data
    if description.malformedKeyUsage {
      usage = Self.malformedIssuerKeyUsage
    } else if description.isCertificateAuthority {
      usage =
        description.allowsCrlSigning
        ? Self.issuerKeyUsage
        : Self.issuerKeyUsageWithoutCrlSign
    } else {
      usage = Self.targetKeyUsage
    }
    var extensions: [Data] = []
    extensions.append(
      Self.extensionValue(
        oid: Self.basicConstraintsOid,
        critical: true,
        value: constraints
      )
    )
    if description.includesKeyUsage {
      extensions.append(
        Self.extensionValue(
          oid: Self.keyUsageOid,
          critical: true,
          value: DerEncoder.tlv(Self.tagBitString, usage)
        )
      )
    }
    return DerEncoder.sequence(extensions)
  }

  /// SubjectPublicKeyInfo for an RSA or named-curve EC public key.
  private static func subjectPublicKeyInfo(
    _ key: SecKey,
    kind: SignatureKind
  ) throws -> Data {
    guard let publicKey = SecKeyCopyPublicKey(key) else {
      throw FixtureFailure.keyCreation
    }
    var error: Unmanaged<CFError>?
    guard
      let representation = SecKeyCopyExternalRepresentation(publicKey, &error)
    else {
      _ = error?.takeRetainedValue()
      throw FixtureFailure.keyCreation
    }
    let algorithm: Data
    if let curveOid = kind.curveOid {
      algorithm = DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.ecPublicKeyOid),
        DerEncoder.objectIdentifier(curveOid),
      ])
    } else {
      algorithm = DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.rsaEncryptionOid),
        DerEncoder.tlv(Self.tagNull, Data()),
      ])
    }
    return DerEncoder.sequence([
      algorithm,
      Self.bitString(representation as Data),
    ])
  }

  /// AlgorithmIdentifier for one supported CRL/certificate signature.
  private static func algorithmIdentifier(_ kind: SignatureKind) -> Data {
    var fields = [DerEncoder.objectIdentifier(kind.algorithmOid)]
    if kind.usesRsaParameters {
      fields.append(DerEncoder.tlv(Self.tagNull, Data()))
    }
    return DerEncoder.sequence(fields)
  }

  /// One revoked target entry, with optional entry extensions.
  private static func revokedCertificates(_ extensions: [Data], serial: Data) -> Data {
    var fields = [
      DerEncoder.unsignedInteger(serial),
      Self.generalizedTime(Self.revocationDate),
    ]
    if !extensions.isEmpty {
      fields.append(DerEncoder.sequence(extensions))
    }
    return DerEncoder.sequence([DerEncoder.sequence(fields)])
  }

  /// DER GeneralizedTime from fixed test text.
  private static func generalizedTime(_ value: String) -> Data {
    DerEncoder.tlv(Self.tagGeneralizedTime, Data(value.utf8))
  }

  /// DER BIT STRING with no unused bits.
  private static func bitString(_ value: Data) -> Data {
    DerEncoder.tlv(Self.tagBitString, Data([0]) + value)
  }

  /// Signs exact DER using Security's message-level algorithms.
  private static func sign(
    _ data: Data,
    with key: SecKey,
    kind: SignatureKind
  ) throws -> Data {
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        key,
        kind.algorithm,
        data as CFData,
        &error
      )
    else {
      _ = error?.takeRetainedValue()
      throw FixtureFailure.signatureCreation
    }
    return signature as Data
  }
}
