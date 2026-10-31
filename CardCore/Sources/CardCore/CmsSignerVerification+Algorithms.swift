// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// The digest and signature algorithms a third-party CMS may name.
extension CmsSignerVerification {
  /// A SignerInfo digest algorithm this verifier accepts.
  internal enum Digest {
    case sha256
    case sha384
    case sha512

    /// The digest output length.
    internal var byteCount: Int {
      switch self {
      case .sha256:
        SHA256.byteCount

      case .sha384:
        SHA384.byteCount

      case .sha512:
        SHA512.byteCount
      }
    }

    /// The digest an AlgorithmIdentifier names, with absent or NULL
    /// parameters; nil for SHA-1, MD5 and every other algorithm.
    internal init?(algorithmIdentifier encoded: Data) {
      switch try? CmsSigningCertificate.digestAlgorithm(encoded) {
      case .sha256:
        self = .sha256

      case .sha384:
        self = .sha384

      case .sha512:
        self = .sha512

      case .sha1, nil:
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

      case .sha512:
        Data(SHA512.hash(data: data))
      }
    }
  }

  /// The public-key family a signature or a key belongs to.
  internal enum KeyFamily {
    case ecdsa
    case rsa

    /// The family of an accepted signer key: RSA of at least the
    /// minimum modulus, or EC on P-256 or P-384; nil otherwise.
    internal init?(_ key: SecKey) {
      guard
        let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
        let type = attributes[kSecAttrKeyType] as? String,
        let bits = attributes[kSecAttrKeySizeInBits] as? Int
      else {
        return nil
      }
      if type == kSecAttrKeyTypeRSA as String, bits >= CmsSignerVerification.minimumRsaKeyBits {
        self = .rsa
      } else if type == kSecAttrKeyTypeECSECPrimeRandom as String,
        CmsSignerVerification.acceptedEcKeyBits.contains(bits)
      {
        self = .ecdsa
      } else {
        return nil
      }
    }
  }

  /// A SignerInfo signature algorithm and the platform operation that
  /// verifies it over the signed attributes.
  internal struct SignatureScheme {
    /// Each accepted signature OID, its key family and the hash it
    /// names, nil for one that names only the key.
    private static let namedSchemes: [String: (KeyFamily, Digest?)] = [
      SignOids.rsaEncryption: (.rsa, nil),
      SignOids.sha256WithRsa: (.rsa, .sha256),
      SignOids.sha384WithRsa: (.rsa, .sha384),
      SignOids.sha512WithRsa: (.rsa, .sha512),
      SignOids.ecPublicKey: (.ecdsa, nil),
      SignOids.ecdsaWithSha256: (.ecdsa, .sha256),
      SignOids.ecdsaWithSha384: (.ecdsa, .sha384),
      SignOids.ecdsaWithSha512: (.ecdsa, .sha512),
    ]

    /// The key family the algorithm needs.
    internal let family: KeyFamily

    /// The message-signature algorithm for the digest.
    internal let algorithm: SecKeyAlgorithm

    /// The scheme `identifier` names under the SignerInfo `digest`, or
    /// nil when it names another hash (RFC 5754 section 3), carries
    /// parameters RFC 5754 or RFC 5758 do not allow, or is unknown.
    ///
    /// rsaEncryption and id-ecPublicKey name only the key; the digest
    /// algorithm then gives the hash.
    internal init?(identifier: Data, digest: Digest) {
      guard
        let (oid, hasNullParameters) = Self.parts(of: identifier),
        let scheme = Self.namedSchemes[oid]
      else {
        return nil
      }
      // RFC 5758 section 3.2: ECDSA identifiers carry no parameters.
      guard scheme.0 == .rsa || !hasNullParameters else { return nil }
      if let hash = scheme.1, hash != digest { return nil }
      family = scheme.0
      algorithm = Self.algorithm(scheme.0, digest)
    }

    /// The dotted OID and whether NULL parameters follow it, nil for
    /// any other parameters.
    private static func parts(of identifier: Data) -> (String, Bool)? {
      for oid in Self.namedSchemes.keys {
        let encoded = DerEncoder.objectIdentifier(oid)
        if identifier == DerEncoder.sequence([encoded]) { return (oid, false) }
        if identifier == DerEncoder.sequence([encoded, DerEncoder.null()]) { return (oid, true) }
      }
      return nil
    }

    /// The platform message-signature algorithm.
    private static func algorithm(_ family: KeyFamily, _ digest: Digest) -> SecKeyAlgorithm {
      switch (family, digest) {
      case (.ecdsa, .sha256):
        .ecdsaSignatureMessageX962SHA256

      case (.ecdsa, .sha384):
        .ecdsaSignatureMessageX962SHA384

      case (.ecdsa, .sha512):
        .ecdsaSignatureMessageX962SHA512

      case (.rsa, .sha256):
        .rsaSignatureMessagePKCS1v15SHA256

      case (.rsa, .sha384):
        .rsaSignatureMessagePKCS1v15SHA384

      case (.rsa, .sha512):
        .rsaSignatureMessagePKCS1v15SHA512
      }
    }
  }
}
