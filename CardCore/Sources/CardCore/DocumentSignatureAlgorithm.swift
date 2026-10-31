// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A SignerInfo signature algorithm the PAdES verifier accepts.
///
/// RSA PKCS#1 v1.5 identifiers are written with NULL parameters and read
/// with NULL or absent ones (RFC 5754 section 3.2); ECDSA identifiers
/// carry none (RFC 5758 section 3.2).
public enum DocumentSignatureAlgorithm: Equatable, Sendable {
  /// ecdsa-with-SHA256 or ecdsa-with-SHA384.
  case ecdsa(DocumentDigestAlgorithm)

  /// id-ecPublicKey, the key algorithm identifier of RFC 5480 section
  /// 2.1.1 that some generators write in place of ecdsa-with-SHA*; the
  /// hash then comes from the SignerInfo digest algorithm.
  case ecPublicKey

  /// sha256WithRSAEncryption or sha384WithRSAEncryption.
  case rsaPkcs1(DocumentDigestAlgorithm)

  /// The DER AlgorithmIdentifier.
  internal var algorithmIdentifier: Data {
    switch self {
    case .rsaPkcs1(.sha256):
      Self.withNull(SignOids.sha256WithRsa)

    case .rsaPkcs1(.sha384):
      Self.withNull(SignOids.sha384WithRsa)

    case .ecdsa(.sha256):
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)])

    case .ecdsa(.sha384):
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha384)])

    case .ecPublicKey:
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecPublicKey)])
    }
  }

  /// The RSA identifier with its parameters absent, nil for ECDSA.
  private var parameterlessRsaIdentifier: Data? {
    switch self {
    case .rsaPkcs1(.sha256):
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha256WithRsa)])

    case .rsaPkcs1(.sha384):
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.sha384WithRsa)])

    case .ecdsa, .ecPublicKey:
      nil
    }
  }

  /// The algorithm a DER AlgorithmIdentifier names, nil for any other
  /// algorithm or parameter form.
  internal init?(algorithmIdentifier encoded: Data) {
    let candidates: [Self] = [
      .rsaPkcs1(.sha256), .rsaPkcs1(.sha384),
      .ecdsa(.sha256), .ecdsa(.sha384),
      .ecPublicKey,
    ]
    guard
      let match = candidates.first(where: { candidate in
        candidate.algorithmIdentifier == encoded
          || candidate.parameterlessRsaIdentifier == encoded
      })
    else {
      return nil
    }
    self = match
  }

  /// The signing algorithm for one card key under one digest.
  internal static func signing(
    _ profile: CardKeyProfile,
    digest: DocumentDigestAlgorithm
  ) -> Self {
    switch profile {
    case .ecdsaP256, .ecdsaP384:
      .ecdsa(digest)

    case .rsa2048, .rsa3072:
      .rsaPkcs1(digest)
    }
  }

  /// One AlgorithmIdentifier with NULL parameters.
  private static func withNull(_ oid: String) -> Data {
    DerEncoder.sequence([DerEncoder.objectIdentifier(oid), DerEncoder.null()])
  }

  /// Whether this algorithm fits a key of `profile` and a SignerInfo
  /// digest of `digest`.
  internal func agrees(
    with profile: CardKeyProfile,
    digest: DocumentDigestAlgorithm
  ) -> Bool {
    switch (self, profile) {
    case (.rsaPkcs1(let named), .rsa2048), (.rsaPkcs1(let named), .rsa3072):
      named == digest

    case (.ecdsa(let named), .ecdsaP256), (.ecdsa(let named), .ecdsaP384):
      named == digest

    case (.ecPublicKey, .ecdsaP256), (.ecPublicKey, .ecdsaP384):
      true

    case (.rsaPkcs1, .ecdsaP256), (.rsaPkcs1, .ecdsaP384),
      (.ecdsa, .rsa2048), (.ecdsa, .rsa3072),
      (.ecPublicKey, .rsa2048), (.ecPublicKey, .rsa3072):
      false
    }
  }
}
