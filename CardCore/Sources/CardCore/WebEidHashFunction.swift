// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Hash functions supported by the Web eID signing and authentication commands.
public enum WebEidHashFunction: String, Codable, CaseIterable, Equatable, Sendable {
  case sha224 = "SHA-224"
  case sha256 = "SHA-256"
  case sha384 = "SHA-384"
  case sha512 = "SHA-512"

  /// Matching `CardCore` signing hash identifier.
  public var signingHash: SigningHash {
    switch self {
    case .sha224:
      .sha224

    case .sha256:
      .sha256

    case .sha384:
      .sha384

    case .sha512:
      .sha512
    }
  }

  /// Required byte length of a pre-computed digest for this hash function.
  public var digestByteCount: Int {
    signingHash.digestByteCount
  }

  /// Security.framework ECDSA digest-verification algorithm matching this hash.
  internal var ecdsaDigestAlgorithm: SecKeyAlgorithm {
    switch self {
    case .sha224:
      .ecdsaSignatureDigestX962SHA224

    case .sha256:
      .ecdsaSignatureDigestX962SHA256

    case .sha384:
      .ecdsaSignatureDigestX962SHA384

    case .sha512:
      .ecdsaSignatureDigestX962SHA512
    }
  }

  /// Security.framework RSA PKCS#1 v1.5 digest-verification algorithm matching this hash.
  internal var rsaPkcs1DigestAlgorithm: SecKeyAlgorithm {
    switch self {
    case .sha224:
      .rsaSignatureDigestPKCS1v15SHA224

    case .sha256:
      .rsaSignatureDigestPKCS1v15SHA256

    case .sha384:
      .rsaSignatureDigestPKCS1v15SHA384

    case .sha512:
      .rsaSignatureDigestPKCS1v15SHA512
    }
  }

  /// Computes the digest of `data` using this hash function (for SHA-256/384/512).
  public func digest(_ data: Data) -> Data? {
    switch self {
    case .sha224:
      nil

    case .sha256:
      Data(SHA256.hash(data: data))

    case .sha384:
      Data(SHA384.hash(data: data))

    case .sha512:
      Data(SHA512.hash(data: data))
    }
  }
}
