// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// A resolved FINEID signature request: card algorithm, digest, response
/// shape, and the local verification algorithm.
public struct SignRequest {
  /// The MSE:SET algorithm to select on the card.
  public let algorithm: SigningAlgorithm

  /// The digest bytes handed to PSO:HASH.
  public let digest: Data

  /// The exact PSO:CDS `Le` when it fits a short APDU.
  public let expectedSignatureLength: ExpectedResponseLength?

  /// The exact raw result size for this key profile.
  public let rawSignatureLength: Int

  /// The Security.framework algorithm used for local verification.
  public let verifyAlgorithm: SecKeyAlgorithm

  /// Builds one fully resolved request after profile validation.
  private init(
    algorithm: SigningAlgorithm,
    digest: Data,
    expectedSignatureLength: ExpectedResponseLength?,
    rawSignatureLength: Int,
    verifyAlgorithm: SecKeyAlgorithm
  ) {
    self.algorithm = algorithm
    self.digest = digest
    self.expectedSignatureLength = expectedSignatureLength
    self.rawSignatureLength = rawSignatureLength
    self.verifyAlgorithm = verifyAlgorithm
  }

  /// Resolves a consistent card request from its certificate profile.
  ///
  /// Callers cannot independently choose response or verification shapes that
  /// disagree with the card key.
  public static func resolve(
    profile: CardKeyProfile,
    algorithm: SigningAlgorithm,
    digest: Data
  ) -> Self? {
    guard digest.count == algorithm.hash.digestByteCount else { return nil }
    let verification: SecKeyAlgorithm
    switch (profile, algorithm.scheme, algorithm.hash) {
    case (.ecdsaP384, .ecdsa, .sha224):
      verification = .ecdsaSignatureDigestX962SHA224

    case (.ecdsaP384, .ecdsa, .sha256):
      verification = .ecdsaSignatureDigestX962SHA256

    case (.ecdsaP384, .ecdsa, .sha384):
      verification = .ecdsaSignatureDigestX962SHA384

    case (.ecdsaP384, .ecdsa, .sha512):
      verification = .ecdsaSignatureDigestX962SHA512

    case (.rsa2048, .rsaPkcs1, .sha256),
      (.rsa3072, .rsaPkcs1, .sha256):
      verification = .rsaSignatureDigestPKCS1v15SHA256

    case (.rsa2048, .rsaPkcs1, .sha384),
      (.rsa3072, .rsaPkcs1, .sha384):
      verification = .rsaSignatureDigestPKCS1v15SHA384

    case (.rsa2048, .rsaPkcs1, .sha512),
      (.rsa3072, .rsaPkcs1, .sha512):
      verification = .rsaSignatureDigestPKCS1v15SHA512

    case (.rsa2048, .rsaPss, .sha256),
      (.rsa3072, .rsaPss, .sha256):
      verification = .rsaSignatureDigestPSSSHA256

    default:
      return nil
    }
    return Self(
      algorithm: algorithm,
      digest: digest,
      expectedSignatureLength: profile.expectedSignatureLength,
      rawSignatureLength: profile.rawSignatureLength,
      verifyAlgorithm: verification
    )
  }

  /// Converts the card result to the form Security.framework and CMS expect.
  ///
  /// ECDSA cards return `r || s`; RSA cards already return the modulus-wide
  /// signature value unchanged.
  public func wireSignature(from raw: Data) -> Data? {
    guard raw.count == rawSignatureLength else { return nil }
    switch algorithm.scheme {
    case .ecdsa:
      return EcdsaSignature.derFromRawConcatenation(raw)

    case .rsaPkcs1, .rsaPss:
      return raw
    }
  }

  /// The signature a paired phone returned, in the form Security.framework
  /// and CMS expect, once it verifies against `publicKey`.
  ///
  /// RAPP v26.10.9 section 9.2 carries the card's raw value (`r || s` for
  /// ECDSA). A phone built before that rule sends DER, which is accepted
  /// when it verifies as it stands.
  public func verifiedRemoteSignature(_ received: Data, from publicKey: SecKey) -> Data? {
    if let wire = wireSignature(from: received), isSatisfied(by: wire, from: publicKey) {
      return wire
    }
    return isSatisfied(by: received, from: publicKey) ? received : nil
  }

  /// Whether `signature` verifies against the resolved digest and public key.
  public func isSatisfied(by signature: Data, from publicKey: SecKey) -> Bool {
    var error: Unmanaged<CFError>?
    return SecKeyVerifySignature(
      publicKey,
      verifyAlgorithm,
      digest as CFData,
      signature as CFData,
      &error
    )
  }
}
