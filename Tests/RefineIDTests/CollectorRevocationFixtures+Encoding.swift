// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation

extension CollectorRevocationFixtures {
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

  /// ASN.1 URI GeneralName.
  private static let tagUri: UInt8 = 0x86

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

  /// id-ce-extKeyUsage.
  private static let extendedKeyUsageOid = "2.5.29.37"

  /// id-kp-timeStamping.
  private static let timestampingKeyPurposeOid = "1.3.6.1.5.5.7.3.8"

  /// id-pe-authorityInfoAccess.
  private static let authorityInfoAccessOid = "1.3.6.1.5.5.7.1.1"

  /// id-ad-caIssuers.
  private static let caIssuersOid = "1.3.6.1.5.5.7.48.2"

  /// id-ce-cRLDistributionPoints.
  private static let crlDistributionPointsOid = "2.5.29.31"

  /// X.509 version value for version 3 certificates.
  private static let certificateVersionThree = 2

  /// X.509 version value for version 2 CRLs.
  private static let crlVersionTwo = 1

  /// The issuer certificate serial.
  private static let issuerSerial = Data([0x01])

  /// The revoked document signer serial.
  private static let documentSignerSerialValue: UInt8 = 2
  private static let documentSignerSerial = Data([
    Self.documentSignerSerialValue
  ])

  /// The revoked timestamp authority serial.
  private static let timestampAuthoritySerialValue: UInt8 = 3
  private static let timestampAuthoritySerial = Data([
    Self.timestampAuthoritySerialValue
  ])

  /// A fixed verification time on 5 August 2026.
  private static let currentTimeInterval: TimeInterval = 1_785_931_200
  private static let currentTime = Date(
    timeIntervalSince1970: Self.currentTimeInterval
  )

  /// One unused bit after keyCertSign and cRLSign.
  private static let oneUnusedBit: UInt8 = 1

  /// DER KeyUsage payload containing keyCertSign and cRLSign.
  private static let keyCertAndCrlSignBits: UInt8 = 6

  /// Seven unused bits after digitalSignature.
  private static let sevenUnusedBits: UInt8 = 7

  /// DER KeyUsage payload containing digitalSignature.
  private static let digitalSignatureBit: UInt8 = 128

  /// DER BOOLEAN TRUE content.
  private static let booleanTrue: UInt8 = 0xFF

  /// Fixed test-only P-256 issuer private key.
  private static let issuerKeyEncoding =
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE="

  /// Fixed test-only P-256 document-signer private key.
  private static let documentKeyEncoding =
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAI="

  /// Fixed test-only P-256 timestamp-authority private key.
  private static let timestampKeyEncoding =
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM="

  /// Generates one complete, cryptographically authenticated fixture.
  internal static func make() throws -> Material {
    let issuerKey = try Self.makeKey(Self.issuerKeyEncoding)
    let documentKey = try Self.makeKey(Self.documentKeyEncoding)
    let timestampKey = try Self.makeKey(Self.timestampKeyEncoding)
    let issuerName = Self.name("RefineID Collector Test CA")
    let issuerCertificate = try Self.certificate(
      CertificateDescription(
        commonName: "RefineID Collector Test CA",
        issuerName: issuerName,
        serial: Self.issuerSerial,
        publicKey: issuerKey,
        signer: issuerKey,
        certificateAuthority: true,
        timestampAuthority: false
      )
    )
    let documentSignerCertificate = try Self.certificate(
      CertificateDescription(
        commonName: "RefineID Collector Document Signer",
        issuerName: issuerName,
        serial: Self.documentSignerSerial,
        publicKey: documentKey,
        signer: issuerKey,
        certificateAuthority: false,
        timestampAuthority: false
      )
    )
    let timestampAuthorityCertificate = try Self.certificate(
      CertificateDescription(
        commonName: "RefineID Collector Timestamp Authority",
        issuerName: issuerName,
        serial: Self.timestampAuthoritySerial,
        publicKey: timestampKey,
        signer: issuerKey,
        certificateAuthority: false,
        timestampAuthority: true
      )
    )
    let revocationList = try Self.revocationList(
      issuerName: issuerName,
      issuerKey: issuerKey
    )
    return Material(
      issuerCertificate: issuerCertificate,
      documentSignerCertificate: documentSignerCertificate,
      timestampAuthorityCertificate: timestampAuthorityCertificate,
      revocationList: revocationList,
      currentTime: Self.currentTime
    )
  }

  /// Constructs one v3 certificate and signs its exact TBSCertificate.
  private static func certificate(
    _ description: CertificateDescription
  ) throws -> Data {
    let algorithm = Self.algorithmIdentifier()
    let extensions = Self.certificateExtensions(
      certificateAuthority: description.certificateAuthority,
      timestampAuthority: description.timestampAuthority
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
        Self.generalizedTime("20250101000000Z"),
        Self.generalizedTime("20300101000000Z"),
      ]),
      Self.name(description.commonName),
      Self.subjectPublicKeyInfo(description.publicKey),
      DerEncoder.tlv(Self.tagContext3Constructed, extensions),
    ])
    return DerEncoder.sequence([
      tbs,
      algorithm,
      Self.bitString(try Self.sign(tbs, with: description.signer)),
    ])
  }

  /// Constructs one issuer-signed CRL listing both generated leaves.
  private static func revocationList(
    issuerName: Data,
    issuerKey: P256.Signing.PrivateKey
  ) throws -> Data {
    let algorithm = Self.algorithmIdentifier()
    let revoked = DerEncoder.sequence([
      Self.revokedCertificate(serial: Self.documentSignerSerial),
      Self.revokedCertificate(serial: Self.timestampAuthoritySerial),
    ])
    let tbs = DerEncoder.sequence([
      DerEncoder.integer(Self.crlVersionTwo),
      algorithm,
      issuerName,
      Self.generalizedTime("20260801000000Z"),
      Self.generalizedTime("20260901000000Z"),
      revoked,
    ])
    return DerEncoder.sequence([
      tbs,
      algorithm,
      Self.bitString(try Self.sign(tbs, with: issuerKey)),
    ])
  }

  /// Certificate extensions for a direct issuer or one tested leaf.
  private static func certificateExtensions(
    certificateAuthority: Bool,
    timestampAuthority: Bool
  ) -> Data {
    let constraints =
      certificateAuthority
      ? DerEncoder.sequence([Self.boolean(true)])
      : DerEncoder.sequence([])
    let usage =
      certificateAuthority
      ? Data([Self.oneUnusedBit, Self.keyCertAndCrlSignBits])
      : Data([Self.sevenUnusedBits, Self.digitalSignatureBit])
    var extensions = [
      Self.extensionValue(
        oid: Self.basicConstraintsOid,
        critical: true,
        value: constraints
      ),
      Self.extensionValue(
        oid: Self.keyUsageOid,
        critical: true,
        value: DerEncoder.tlv(Self.tagBitString, usage)
      ),
    ]
    if !certificateAuthority {
      extensions.append(Self.authorityInfoAccessExtension())
      extensions.append(Self.revocationListExtension())
    }
    if timestampAuthority {
      extensions.append(
        Self.extensionValue(
          oid: Self.extendedKeyUsageOid,
          critical: true,
          value: DerEncoder.sequence([
            DerEncoder.objectIdentifier(Self.timestampingKeyPurposeOid)
          ])
        )
      )
    }
    return DerEncoder.sequence(extensions)
  }

  /// An AIA caIssuers access description for the generated issuer.
  private static func authorityInfoAccessExtension() -> Data {
    let description = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.caIssuersOid),
      DerEncoder.tlv(Self.tagUri, Data(Self.issuerAddress.utf8)),
    ])
    return Self.extensionValue(
      oid: Self.authorityInfoAccessOid,
      critical: false,
      value: DerEncoder.sequence([description])
    )
  }

  /// One full-name CRL distribution point.
  private static func revocationListExtension() -> Data {
    let names = DerEncoder.tlv(
      Self.tagUri,
      Data(Self.revocationListAddress.utf8)
    )
    let pointName = DerEncoder.tlv(
      Self.tagContext0Constructed,
      DerEncoder.tlv(Self.tagContext0Constructed, names)
    )
    let point = DerEncoder.sequence([pointName])
    return Self.extensionValue(
      oid: Self.crlDistributionPointsOid,
      critical: false,
      value: DerEncoder.sequence([point])
    )
  }

  /// One revoked-certificate entry.
  private static func revokedCertificate(serial: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.unsignedInteger(serial),
      Self.generalizedTime("20260801000000Z"),
    ])
  }

  /// Builds one X.509 Extension value.
  private static func extensionValue(
    oid: String,
    critical: Bool,
    value: Data
  ) -> Data {
    var fields = [DerEncoder.objectIdentifier(oid)]
    if critical {
      fields.append(Self.boolean(true))
    }
    fields.append(DerEncoder.octetString(value))
    return DerEncoder.sequence(fields)
  }

  /// SubjectPublicKeyInfo for a P-256 key.
  private static func subjectPublicKeyInfo(
    _ key: P256.Signing.PrivateKey
  ) -> Data {
    let algorithm = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.ecPublicKeyOid),
      DerEncoder.objectIdentifier(Self.p256CurveOid),
    ])
    return DerEncoder.sequence([
      algorithm,
      Self.bitString(key.publicKey.x963Representation),
    ])
  }

  /// The ECDSA-with-SHA256 AlgorithmIdentifier.
  private static func algorithmIdentifier() -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.ecdsaSha256Oid)
    ])
  }

  /// Encodes a distinguished Name containing one commonName attribute.
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

  /// Restores one fixed test-only P-256 private key.
  private static func makeKey(
    _ encoded: String
  ) throws -> P256.Signing.PrivateKey {
    guard let raw = Data(base64Encoded: encoded) else {
      throw Failure.invalidKeyEncoding
    }
    return try P256.Signing.PrivateKey(rawRepresentation: raw)
  }

  /// Signs exact DER with ECDSA and SHA-256.
  private static func sign(
    _ data: Data,
    with key: P256.Signing.PrivateKey
  ) throws -> Data {
    try key.signature(for: data).derRepresentation
  }
}
