// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security

/// Generated certificates and CRLs used only by direct validator tests.
internal enum CertificateRevocationListFixtures {
  /// Signature schemes the CRL validator promises to authenticate.
  internal enum SignatureKind: CaseIterable, Sendable {
    /// ECDSA with SHA-256 on P-256.
    case ecdsaSha256

    /// ECDSA with SHA-384 on P-384.
    case ecdsaSha384

    /// ECDSA with SHA-512 on P-521.
    case ecdsaSha512

    /// RSA PKCS#1 v1.5 with SHA-256.
    case rsaSha256

    /// RSA PKCS#1 v1.5 with SHA-384.
    case rsaSha384

    /// RSA PKCS#1 v1.5 with SHA-512.
    case rsaSha512

    /// P-256 key size.
    private static let p256KeySize = 256

    /// P-384 key size.
    private static let p384KeySize = 384

    /// P-521 key size.
    private static let p521KeySize = 521

    /// RSA test key size.
    private static let rsaKeySize = 2_048

    /// Security signature algorithm matching this fixture kind.
    internal var algorithm: SecKeyAlgorithm {
      switch self {
      case .ecdsaSha256:
        .ecdsaSignatureMessageX962SHA256

      case .ecdsaSha384:
        .ecdsaSignatureMessageX962SHA384

      case .ecdsaSha512:
        .ecdsaSignatureMessageX962SHA512

      case .rsaSha256:
        .rsaSignatureMessagePKCS1v15SHA256

      case .rsaSha384:
        .rsaSignatureMessagePKCS1v15SHA384

      case .rsaSha512:
        .rsaSignatureMessagePKCS1v15SHA512
      }
    }

    /// Key size accepted by Security for the signature kind.
    internal var keySize: Int {
      switch self {
      case .ecdsaSha256:
        Self.p256KeySize

      case .ecdsaSha384:
        Self.p384KeySize

      case .ecdsaSha512:
        Self.p521KeySize

      case .rsaSha256, .rsaSha384, .rsaSha512:
        Self.rsaKeySize
      }
    }

    /// Security key family for this signature kind.
    internal var keyType: CFString {
      switch self {
      case .ecdsaSha256, .ecdsaSha384, .ecdsaSha512:
        kSecAttrKeyTypeECSECPrimeRandom

      case .rsaSha256, .rsaSha384, .rsaSha512:
        kSecAttrKeyTypeRSA
      }
    }

    /// Whether AlgorithmIdentifier carries explicit NULL parameters.
    internal var usesRsaParameters: Bool {
      switch self {
      case .ecdsaSha256, .ecdsaSha384, .ecdsaSha512:
        false

      case .rsaSha256, .rsaSha384, .rsaSha512:
        true
      }
    }
  }

  /// Inputs and expected authenticated output for one generated list.
  internal struct Material: Sendable {
    /// The leaf certificate whose status is checked.
    internal let certificate: Data

    /// The CRL in DER form.
    internal let crl: Data

    /// The same CRL in a standard PEM envelope.
    internal let crlPem: Data

    /// The self-signed issuer certificate.
    internal let issuerCertificate: Data

    /// A point inside the standard CRL validity window.
    internal let currentTime: Date
  }

  /// KeyUsage variants carried by the generated issuer certificate.
  internal enum IssuerKeyUsage {
    /// The optional KeyUsage extension is absent.
    case absent

    /// KeyUsage authorizes CRL signing.
    case crlSigning

    /// KeyUsage has nonzero bits that its unused-bit count declares unused.
    case malformedUnusedBits

    /// KeyUsage is present without cRLSign.
    case withoutCrlSigning

    /// Whether KeyUsage asserts cRLSign.
    internal var allowsCrlSigning: Bool {
      self == .crlSigning || self == .malformedUnusedBits
    }

    /// Whether the certificate carries a KeyUsage extension.
    internal var includesExtension: Bool {
      self != .absent
    }

    /// Whether the unused-bit count contradicts the final content byte.
    internal var isMalformed: Bool {
      self == .malformedUnusedBits
    }
  }

  /// Controllable CRL fields for negative tests.
  internal struct Options {
    /// The issuer name shared by normal certificate and CRL fixtures.
    private static let issuerCommonName = "RefineID CRL Test CA"

    /// A future boundary relative to the fixed verification time.
    private static let standardNextUpdate = "20260901000000Z"

    /// A past boundary relative to the fixed verification time.
    private static let standardThisUpdate = "20260501000000Z"

    /// A normal unscoped, non-revoking CRL.
    internal static var standard: Self {
      Self(
        crlExtensions: [],
        crlIssuerCommonName: Self.issuerCommonName,
        entryExtensions: [],
        includesNextUpdate: true,
        listsTargetSerial: false,
        nextUpdate: Self.standardNextUpdate,
        thisUpdate: Self.standardThisUpdate
      )
    }

    /// CRL-wide extensions, already encoded as Extension values.
    internal var crlExtensions: [Data]

    /// The issuer common name placed in TBSCertList.
    internal var crlIssuerCommonName: String

    /// Extensions placed on the target's revoked entry.
    internal var entryExtensions: [Data]

    /// Whether nextUpdate is emitted.
    internal var includesNextUpdate: Bool

    /// Whether the target serial occurs in revokedCertificates.
    internal var listsTargetSerial: Bool

    /// The fixed GeneralizedTime used for nextUpdate.
    internal var nextUpdate: String

    /// The fixed GeneralizedTime used for thisUpdate.
    internal var thisUpdate: String
  }

  /// Fields that differ between generated issuer and target certificates.
  internal struct CertificateDescription {
    /// Whether KeyUsage asserts cRLSign.
    internal let allowsCrlSigning: Bool

    /// Whether an end entity explicitly encodes BasicConstraints cA FALSE.
    internal var explicitFalseBasicConstraint = false

    /// Whether the certificate carries a KeyUsage extension at all.
    internal let includesKeyUsage: Bool

    /// Whether KeyUsage deliberately leaves declared unused bits nonzero.
    internal let malformedKeyUsage: Bool

    /// The subject common name.
    internal let commonName: String

    /// Whether BasicConstraints marks this certificate as a CA.
    internal let isCertificateAuthority: Bool

    /// The already encoded issuer Name.
    internal let issuerName: Data

    /// The positive certificate serial magnitude.
    internal let serial: Data
  }

  /// Errors produced only while constructing test material.
  internal enum FixtureFailure: Error {
    /// Security could not create or export a key.
    case keyCreation

    /// Security could not make a signature.
    case signatureCreation
  }

  /// One positive target serial shared by the certificate and CRL entries.
  internal static let targetSerial = Data([UInt8(ascii: "*")])

  /// id-ce-deltaCRLIndicator.
  internal static let deltaCrlIndicatorOid = "2.5.29.27"

  /// id-ce-issuingDistributionPoint.
  internal static let issuingDistributionPointOid = "2.5.29.28"

  /// id-ce-certificateIssuer.
  internal static let certificateIssuerOid = "2.5.29.29"

  /// A private test OID with no validator semantics.
  internal static let unknownExtensionOid = "1.3.6.1.4.1.55555.1"

  /// ASN.1 primitive context tag `[1]`.
  internal static let tagContext1Primitive: UInt8 = 0x81

  /// ASN.1 primitive context tag `[4]`.
  internal static let tagContext4Primitive: UInt8 = 0x84

  /// DER BOOLEAN TRUE content.
  internal static let booleanTrue: UInt8 = 0xFF

  /// The issuer common name used in certificates and normal CRLs.
  internal static let issuerCommonName = "RefineID CRL Test CA"

  /// The target certificate common name.
  internal static let targetCommonName = "RefineID CRL Test Leaf"

  /// A positive serial for the test root.
  private static let issuerSerial = Data([0x01])

  /// 2026-06-01T00:00:00Z.
  private static let currentTimeInterval: TimeInterval = 1_780_272_000

  /// Generates one complete certificate/CRL relationship.
  internal static func make(
    kind: SignatureKind,
    options: Options,
    targetSignedByWrongKey: Bool,
    issuerKeyUsage: IssuerKeyUsage
  ) throws -> Material {
    try Self.make(
      kind: kind,
      options: options,
      targetSignedByWrongKey: targetSignedByWrongKey,
      issuerKeyUsage: issuerKeyUsage,
      explicitFalseBasicConstraint: false
    )
  }

  /// The same fixture with explicit control over the end-entity default.
  internal static func make(
    kind: SignatureKind,
    options: Options,
    targetSignedByWrongKey: Bool,
    issuerKeyUsage: IssuerKeyUsage,
    explicitFalseBasicConstraint: Bool
  ) throws -> Material {
    let issuerKey = try Self.makeKey(for: kind)
    let targetKey = try Self.makeKey(for: kind)
    let issuerName = Self.name(Self.issuerCommonName)
    let issuer = try Self.certificate(
      description: CertificateDescription(
        allowsCrlSigning: issuerKeyUsage.allowsCrlSigning,
        includesKeyUsage: issuerKeyUsage.includesExtension,
        malformedKeyUsage: issuerKeyUsage.isMalformed,
        commonName: Self.issuerCommonName,
        isCertificateAuthority: true,
        issuerName: issuerName,
        serial: Self.issuerSerial
      ),
      publicKey: issuerKey,
      signer: issuerKey,
      kind: kind
    )
    let targetSigner =
      targetSignedByWrongKey
      ? try Self.makeKey(for: kind)
      : issuerKey
    let target = try Self.certificate(
      description: CertificateDescription(
        allowsCrlSigning: false,
        explicitFalseBasicConstraint: explicitFalseBasicConstraint,
        includesKeyUsage: true,
        malformedKeyUsage: false,
        commonName: Self.targetCommonName,
        isCertificateAuthority: false,
        issuerName: issuerName,
        serial: Self.targetSerial
      ),
      publicKey: targetKey,
      signer: targetSigner,
      kind: kind
    )
    let crl = try Self.crl(
      issuerKey: issuerKey,
      kind: kind,
      options: options
    )
    return Material(
      certificate: target,
      crl: crl,
      crlPem: Self.pem(crl),
      issuerCertificate: issuer,
      currentTime: Date(timeIntervalSince1970: Self.currentTimeInterval)
    )
  }

  /// Builds one X.509 Extension value.
  internal static func extensionValue(
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

  /// Generates a private key matching one test signature kind.
  internal static func makeKey(for kind: SignatureKind) throws -> SecKey {
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kind.keyType,
      kSecAttrKeySizeInBits: kind.keySize,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      _ = error?.takeRetainedValue()
      throw FixtureFailure.keyCreation
    }
    return key
  }
}
