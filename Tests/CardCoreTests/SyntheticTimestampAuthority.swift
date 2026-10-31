// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Security

  @testable import CardCore

  /// A generated timestamping-only identity that mints RFC 3161 tokens
  /// over any SHA-384 imprint, at a chosen generation time.
  ///
  /// The certificate is self-signed and embedded in each token, so
  /// `TimestampTokenVerifier.verify(_:)` anchors on it.
  internal struct SyntheticTimestampAuthority {
    /// The test identity could not be constructed.
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
    private static let commonName = "RefineID Synthetic Timestamp Test"
    private static let notBefore = "20250101000000Z"
    private static let notAfter = "20300101000000Z"
    private static let testPolicyOid = "1.2.3.4.5"
    private static let ecPublicKeyOid = "1.2.840.10045.2.1"
    private static let prime256v1Oid = "1.2.840.10045.3.1.7"
    private static let nonce = Data("synthetic nonce".utf8)

    /// GeneralizedTime spelling of a token generation time.
    internal static let generalizedTimeFormat = "yyyyMMddHHmmss'Z'"

    private static var sha256Algorithm: Data {
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha256), DerEncoder.null()])
    }

    private static var ecdsaSha256Algorithm: Data {
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)])
    }

    private let certificate: Data
    private let key: SecKey
    private let name: Data

    /// Creates a fresh P-256 key and its timestamping-only certificate.
    internal init() throws {
      let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits: Self.p256KeySize,
      ]
      var error: Unmanaged<CFError>?
      guard let generated = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        _ = error?.takeRetainedValue()
        throw Failure.key
      }
      let attribute = DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.commonName),
        DerEncoder.tlv(DerValues.tagUtf8String, Data(Self.commonName.utf8)),
      ])
      let encodedName = DerEncoder.sequence([DerEncoder.setOf([attribute])])
      key = generated
      name = encodedName
      certificate = try Self.certificate(key: generated, name: encodedName)
    }

    /// The instant a GeneralizedTime string names, in UTC.
    internal static func instant(_ generalizedTime: String) -> Date? {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = Self.generalizedTimeFormat
      return formatter.date(from: generalizedTime)
    }

    private static func attribute(_ oid: String, _ value: Data) -> Data {
      DerEncoder.sequence([DerEncoder.objectIdentifier(oid), DerEncoder.setOf([value])])
    }

    private static func sign(_ value: Data, key: SecKey) throws -> Data {
      var error: Unmanaged<CFError>?
      guard
        let signature = SecKeyCreateSignature(
          key, .ecdsaSignatureMessageX962SHA256, value as CFData, &error)
      else {
        _ = error?.takeRetainedValue()
        throw Failure.signature
      }
      return signature as Data
    }

    private static func certificate(key: SecKey, name: Data) throws -> Data {
      guard let publicKey = SecKeyCopyPublicKey(key) else { throw Failure.key }
      var error: Unmanaged<CFError>?
      guard let point = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
        _ = error?.takeRetainedValue()
        throw Failure.key
      }
      let spki = DerEncoder.sequence([
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(Self.ecPublicKeyOid),
          DerEncoder.objectIdentifier(Self.prime256v1Oid),
        ]),
        Self.bitString(point),
      ])
      let signatureUsage = UInt8(1) << UInt8(Self.digitalSignatureBitOffset)
      let extensions = [
        Self.criticalExtension(SignOids.basicConstraints, DerEncoder.sequence([])),
        Self.criticalExtension(
          SignOids.keyUsage, DerEncoder.tlv(DerValues.tagBitString, Data([0, signatureUsage]))),
        Self.criticalExtension(
          SignOids.extendedKeyUsage,
          DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.timestampingKeyPurpose)])),
      ]
      let tbs = DerEncoder.sequence([
        DerEncoder.tlv(
          DerValues.tagContext0Constructed, DerEncoder.integer(Self.x509VersionThree)),
        DerEncoder.integer(Self.certificateSerial),
        Self.ecdsaSha256Algorithm,
        name,
        DerEncoder.sequence([
          DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(Self.notBefore.utf8)),
          DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(Self.notAfter.utf8)),
        ]),
        name,
        spki,
        DerEncoder.tlv(DerValues.tagContext3Constructed, DerEncoder.sequence(extensions)),
      ])
      return DerEncoder.sequence([
        tbs, Self.ecdsaSha256Algorithm, Self.bitString(try Self.sign(tbs, key: key)),
      ])
    }

    private static func criticalExtension(_ oid: String, _ value: Data) -> Data {
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(oid), DerEncoder.booleanTrue(), DerEncoder.octetString(value),
      ])
    }

    private static func bitString(_ value: Data) -> Data {
      DerEncoder.tlv(DerValues.tagBitString, Data([0]) + value)
    }

    /// An RFC 3161 token over the SHA-384 `imprint`, generated at
    /// `generalizedTime`.
    internal func token(imprint: Data, generalizedTime: String) throws -> Data {
      let tstInfo = DerEncoder.sequence([
        DerEncoder.integer(SignOids.tstInfoVersion),
        DerEncoder.objectIdentifier(Self.testPolicyOid),
        DerEncoder.sequence([
          DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha384)]),
          DerEncoder.octetString(imprint),
        ]),
        DerEncoder.integer(Self.timestampSerial),
        DerEncoder.tlv(DerValues.tagGeneralizedTime, Data(generalizedTime.utf8)),
        DerEncoder.unsignedInteger(Self.nonce),
      ])
      let certificateIdentifier = DerEncoder.sequence([
        DerEncoder.octetString(Data(SHA256.hash(data: certificate)))
      ])
      let attributes = DerEncoder.setOf([
        Self.attribute(SignOids.contentType, DerEncoder.objectIdentifier(SignOids.tstInfo)),
        Self.attribute(
          SignOids.messageDigest, DerEncoder.octetString(Data(SHA256.hash(data: tstInfo)))),
        Self.attribute(
          SignOids.signingCertificateV2,
          DerEncoder.sequence([DerEncoder.sequence([certificateIdentifier])])),
      ])
      let signature = try Self.sign(attributes, key: key)
      let signer = DerEncoder.sequence([
        DerEncoder.integer(SignOids.signerInfoVersion),
        DerEncoder.sequence([name, DerEncoder.integer(Self.certificateSerial)]),
        Self.sha256Algorithm,
        DerEncoder.retagged(attributes, to: DerValues.tagContext0Constructed),
        Self.ecdsaSha256Algorithm,
        DerEncoder.octetString(signature),
      ])
      let signedData = DerEncoder.sequence([
        DerEncoder.integer(Self.signedDataVersion),
        DerEncoder.setOf([Self.sha256Algorithm]),
        DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.tstInfo),
          DerEncoder.tlv(DerValues.tagContext0Constructed, DerEncoder.octetString(tstInfo)),
        ]),
        DerEncoder.retagged(
          DerEncoder.setOf([certificate]), to: DerValues.tagContext0Constructed),
        DerEncoder.setOf([signer]),
      ])
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.signedData),
        DerEncoder.tlv(DerValues.tagContext0Constructed, signedData),
      ])
    }
  }

#endif
