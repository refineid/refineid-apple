// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Security

  @testable import CardCore

  /// A generated timestamping-only identity for hermetic signing tests.
  internal struct DebugTimestampAuthority {
    /// Failures mean the test identity could not be constructed.
    internal enum Failure: Error {
      case certificate
      case key
      case signature
    }

    internal static let p256KeySize = 256
    internal static let x509VersionThree = 2
    internal static let certificateSerial = 7
    internal static let timestampSerial = 11
    internal static let signedDataVersion = 3
    internal static let grantedStatus = 0
    internal static let digitalSignatureBitOffset = 7
    internal static let commonName = "RefineID Debug Timestamp Test"
    internal static let generationTime = "20260805100000Z"
    internal static let notBefore = "20250101000000Z"
    internal static let notAfter = "20300101000000Z"
    internal static let testPolicyOid = "1.2.3.4.5"
    internal static let ecPublicKeyOid = "1.2.840.10045.2.1"
    internal static let prime256v1Oid = "1.2.840.10045.3.1.7"

    /// SHA-256 AlgorithmIdentifier.
    internal static var sha256Algorithm: Data {
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.sha256),
        DerEncoder.null(),
      ])
    }

    /// ECDSA-with-SHA-256 AlgorithmIdentifier.
    internal static var ecdsaSha256Algorithm: Data {
      DerEncoder.sequence([
        DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)
      ])
    }

    /// The self-signed timestamping certificate.
    internal let certificate: Data

    /// Its generated private key.
    internal let key: SecKey

    /// Its exact issuer and subject name.
    internal let name: Data

    /// Creates a fresh P-256 key and timestamping-only certificate.
    internal static func make() throws -> Self {
      let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits: Self.p256KeySize,
      ]
      var error: Unmanaged<CFError>?
      guard
        let generatedKey = SecKeyCreateRandomKey(
          attributes as CFDictionary,
          &error
        )
      else {
        _ = error?.takeRetainedValue()
        throw Failure.key
      }
      let encodedName = Self.encodedName(Self.commonName)
      let encodedCertificate = try Self.certificate(
        key: generatedKey,
        name: encodedName
      )
      guard
        SecCertificateCreateWithData(nil, encodedCertificate as CFData) != nil
      else {
        throw Failure.certificate
      }
      return Self(
        certificate: encodedCertificate,
        key: generatedKey,
        name: encodedName
      )
    }

    /// Creates one Security.framework signature.
    internal static func sign(
      _ value: Data,
      key: SecKey,
      algorithm: SecKeyAlgorithm
    ) throws -> Data {
      var error: Unmanaged<CFError>?
      guard
        let signature = SecKeyCreateSignature(
          key,
          algorithm,
          value as CFData,
          &error
        )
      else {
        _ = error?.takeRetainedValue()
        throw Failure.signature
      }
      return signature as Data
    }
  }

#endif
