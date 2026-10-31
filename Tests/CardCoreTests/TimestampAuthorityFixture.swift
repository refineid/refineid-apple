// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

@testable import CardCore

/// A generated, self-signed, timestamping-only authority that mints
/// RFC 3161 tokens over a chosen message imprint.
internal struct TimestampAuthorityFixture {
  /// The test authority could not be constructed.
  internal enum Failure: Error {
    case key
    case signature
  }

  private static let p256KeySize = 256
  private static let x509VersionThree = 2
  private static let certificateSerial = 7
  private static let timestampSerial = 11
  private static let signedDataVersion = 3
  private static let digitalSignatureBitOffset = 7
  private static let commonName = "Test Timestamp Authority"
  private static let generationTime = "20260805100000Z"
  private static let notBefore = "20250101000000Z"
  private static let notAfter = "20300101000000Z"
  private static let testPolicyOid = "1.2.3.4.5"

  /// SHA-256 AlgorithmIdentifier for the authority's own CMS.
  private static var sha256Algorithm: Data {
    DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha256)])
  }

  /// ECDSA-with-SHA-256 AlgorithmIdentifier.
  private static var ecdsaSha256Algorithm: Data {
    DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)])
  }

  /// The authority's issuer and subject Name.
  private static var name: Data {
    DerEncoder.sequence([
      DerEncoder.setOf([
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.commonName),
          DerEncoder.tlv(DerValues.tagUtf8String, Data(Self.commonName.utf8)),
        ])
      ])
    ])
  }

  /// Timestamping-only end-entity extensions.
  private static var extensions: Data {
    let signatureUsage = UInt8(1) << UInt8(Self.digitalSignatureBitOffset)
    return DerEncoder.sequence([
      Self.criticalExtension(
        SignOids.basicConstraints, value: DerEncoder.sequence([])
      ),
      Self.criticalExtension(
        SignOids.keyUsage,
        value: DerEncoder.tlv(DerValues.tagBitString, Data([0, signatureUsage]))
      ),
      Self.criticalExtension(
        SignOids.extendedKeyUsage,
        value: DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.timestampingKeyPurpose)
        ])
      ),
    ])
  }

  /// The self-signed timestamping certificate.
  internal let certificate: Data

  /// Its generated private key.
  private let key: SecKey

  /// Creates a fresh P-256 key and its timestamping certificate.
  internal static func make() throws -> Self {
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits: Self.p256KeySize,
    ]
    var error: Unmanaged<CFError>?
    guard
      let generated = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    else {
      _ = error?.takeRetainedValue()
      throw Failure.key
    }
    let tbs = DerEncoder.sequence([
      DerEncoder.tlv(
        DerValues.tagContext0Constructed,
        DerEncoder.integer(Self.x509VersionThree)
      ),
      DerEncoder.integer(Self.certificateSerial),
      Self.ecdsaSha256Algorithm,
      Self.name,
      DerEncoder.sequence([
        Self.generalizedTime(Self.notBefore),
        Self.generalizedTime(Self.notAfter),
      ]),
      Self.name,
      try Self.subjectPublicKeyInfo(generated),
      DerEncoder.tlv(DerValues.tagContext3Constructed, Self.extensions),
    ])
    let encoded = DerEncoder.sequence([
      tbs,
      Self.ecdsaSha256Algorithm,
      Self.bitString(try Self.sign(tbs, key: generated)),
    ])
    return Self(certificate: encoded, key: generated)
  }

  /// The TSTInfo binding `imprint` under the hash `algorithm` names.
  private static func tstInfo(imprint: Data, algorithm: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.integer(SignOids.tstInfoVersion),
      DerEncoder.objectIdentifier(Self.testPolicyOid),
      DerEncoder.sequence([
        algorithm, DerEncoder.octetString(imprint),
      ]),
      DerEncoder.integer(Self.timestampSerial),
      Self.generalizedTime(Self.generationTime),
    ])
  }

  /// The authority's signed attributes over `tstInfo`.
  private static func signedAttributes(
    tstInfo: Data,
    certificate: Data
  ) -> Data {
    DerEncoder.setOf([
      Self.attribute(
        SignOids.contentType, value: DerEncoder.objectIdentifier(SignOids.tstInfo)
      ),
      Self.attribute(
        SignOids.messageDigest,
        value: DerEncoder.octetString(Data(SHA256.hash(data: tstInfo)))
      ),
      Self.attribute(
        SignOids.signingCertificateV2,
        value: DerEncoder.sequence([
          DerEncoder.sequence([
            DerEncoder.sequence([
              DerEncoder.octetString(Data(SHA256.hash(data: certificate)))
            ])
          ])
        ])
      ),
    ])
  }

  /// One ECDSA P-256 SHA-256 signature over `value`.
  private static func sign(_ value: Data, key: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        key, .ecdsaSignatureMessageX962SHA256, value as CFData, &error
      )
    else {
      _ = error?.takeRetainedValue()
      throw Failure.signature
    }
    return signature as Data
  }

  /// SubjectPublicKeyInfo for one generated P-256 public key.
  private static func subjectPublicKeyInfo(_ key: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard
      let publicKey = SecKeyCopyPublicKey(key),
      let encoded = SecKeyCopyExternalRepresentation(publicKey, &error)
    else {
      _ = error?.takeRetainedValue()
      throw Failure.key
    }
    return DerEncoder.sequence([
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.ecPublicKey),
        DerEncoder.objectIdentifier(SignOids.prime256v1),
      ]),
      Self.bitString(encoded as Data),
    ])
  }

  /// One CMS attribute with exactly one value.
  private static func attribute(_ oid: String, value: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(oid), DerEncoder.setOf([value]),
    ])
  }

  /// One critical X.509 extension.
  private static func criticalExtension(_ oid: String, value: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(oid),
      DerEncoder.booleanTrue(),
      DerEncoder.octetString(value),
    ])
  }

  /// DER GeneralizedTime.
  private static func generalizedTime(_ value: String) -> Data {
    DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(value.utf8))
  }

  /// DER BIT STRING with zero unused bits.
  private static func bitString(_ value: Data) -> Data {
    DerEncoder.tlv(DerValues.tagBitString, Data([0]) + value)
  }

  /// One RFC 3161 TimeStampToken whose messageImprint names the
  /// AlgorithmIdentifier `algorithm` and carries `imprint`.
  internal func token(imprint: Data, algorithm: Data) throws -> Data {
    let tstInfo = Self.tstInfo(imprint: imprint, algorithm: algorithm)
    let attributes = Self.signedAttributes(
      tstInfo: tstInfo, certificate: certificate
    )
    let signer = DerEncoder.sequence([
      DerEncoder.integer(SignOids.signerInfoVersion),
      DerEncoder.sequence([
        Self.name, DerEncoder.integer(Self.certificateSerial),
      ]),
      Self.sha256Algorithm,
      DerEncoder.retagged(attributes, to: DerValues.tagContext0Constructed),
      Self.ecdsaSha256Algorithm,
      DerEncoder.octetString(try Self.sign(attributes, key: key)),
    ])
    let signedData = DerEncoder.sequence([
      DerEncoder.integer(Self.signedDataVersion),
      DerEncoder.setOf([Self.sha256Algorithm]),
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.tstInfo),
        DerEncoder.tlv(
          DerValues.tagContext0Constructed, DerEncoder.octetString(tstInfo)
        ),
      ]),
      DerEncoder.retagged(
        DerEncoder.setOf([certificate]), to: DerValues.tagContext0Constructed
      ),
      DerEncoder.setOf([signer]),
    ])
    return DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.signedData),
      DerEncoder.tlv(DerValues.tagContext0Constructed, signedData),
    ])
  }
}
