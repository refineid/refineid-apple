// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// A digest algorithm the PAdES verifier accepts: SHA-256 or SHA-384
/// (RFC 5754).
///
/// The SignerInfo digest algorithm digests the byte ranges, the signed
/// attributes and the signer certificate in the ESS
/// signing-certificate-v2 attribute (ETSI EN 319 142-1 clause 6.3,
/// table 1 and requirement e)). A timestamp token names its own
/// messageImprint algorithm (RFC 3161 section 2.4.2).
public enum DocumentDigestAlgorithm: Equatable, Sendable {
  case sha256
  case sha384

  /// The digest length in bytes.
  internal var byteCount: Int {
    switch self {
    case .sha256:
      SHA256.byteCount

    case .sha384:
      SHA384.byteCount
    }
  }

  /// The AlgorithmIdentifier with absent parameters (RFC 5754 section 2).
  internal var algorithmIdentifier: Data {
    switch self {
    case .sha256:
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha256)])

    case .sha384:
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha384)])
    }
  }

  /// The algorithm named by a DER AlgorithmIdentifier, nil for any
  /// other hash.
  ///
  /// RFC 5754 section 2 has the parameters absent, and a NULL is
  /// accepted.
  internal init?(algorithmIdentifier encoded: Data) {
    switch try? CmsSigningCertificate.digestAlgorithm(encoded) {
    case .sha256:
      self = .sha256

    case .sha384:
      self = .sha384

    case .sha1, .sha512, nil:
      return nil
    }
  }

  /// The digest of `data`.
  internal func hash(_ data: Data) -> Data {
    switch self {
    case .sha256:
      Data(SHA256.hash(data: data))

    case .sha384:
      Data(SHA384.hash(data: data))
    }
  }

  /// The ESSCertIDv2 binding `certificate` (RFC 5035 section 4).
  ///
  /// The hashAlgorithm field defaults to SHA-256 (ETSI EN 319 122-1
  /// clause 5.2.2.3), and DER omits a value equal to its DEFAULT
  /// (ITU-T X.690 clause 11.5), so it is written only for SHA-384.
  internal func essCertIdV2(certificate: Data) -> Data {
    let certificateHash = DerEncoder.octetString(self.hash(certificate))
    switch self {
    case .sha256:
      return DerEncoder.sequence([certificateHash])

    case .sha384:
      return DerEncoder.sequence([self.algorithmIdentifier, certificateHash])
    }
  }

  /// The Security algorithm that verifies a signature over a digest of
  /// this algorithm with a key of `profile`: X9.62 ECDSA or RSA PKCS#1
  /// v1.5.
  internal func verificationAlgorithm(
    for profile: CardKeyProfile
  ) -> SecKeyAlgorithm {
    switch (profile, self) {
    case (.ecdsaP256, .sha256), (.ecdsaP384, .sha256):
      .ecdsaSignatureDigestX962SHA256

    case (.ecdsaP256, .sha384), (.ecdsaP384, .sha384):
      .ecdsaSignatureDigestX962SHA384

    case (.rsa2048, .sha256), (.rsa3072, .sha256):
      .rsaSignatureDigestPKCS1v15SHA256

    case (.rsa2048, .sha384), (.rsa3072, .sha384):
      .rsaSignatureDigestPKCS1v15SHA384
    }
  }
}
