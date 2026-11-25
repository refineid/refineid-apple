// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Cryptographic helpers for Web eID authentication tokens and document-hash
/// signatures (Web eID architecture specification v1.0).
public enum WebEidCrypto {
  /// Authentication algorithm selection for one card key profile.
  public struct AuthParameters: Equatable, Sendable {
    /// JWS algorithm identifier reported in the Web eID auth token.
    public let jwsAlgorithm: String

    /// Hash function applied to origin, nonce, and their concatenated digests.
    public let hashFunction: WebEidHashFunction

    /// Matching smart-card signing algorithm.
    public let cardAlgorithm: SigningAlgorithm
  }

  /// Selects the JWS authentication algorithm and card signing algorithm
  /// matching `profile`.
  public static func authParameters(for profile: CardKeyProfile) -> AuthParameters {
    switch profile {
    case .ecdsaP384:
      return AuthParameters(
        jwsAlgorithm: WebEidValues.jwsEs384,
        hashFunction: .sha384,
        cardAlgorithm: SigningAlgorithm(hash: .sha384, scheme: .ecdsa)
      )

    case .ecdsaP256:
      return AuthParameters(
        jwsAlgorithm: WebEidValues.jwsEs256,
        hashFunction: .sha256,
        cardAlgorithm: SigningAlgorithm(hash: .sha256, scheme: .ecdsa)
      )

    case .rsa2048, .rsa3072:
      return AuthParameters(
        jwsAlgorithm: WebEidValues.jwsRs256,
        hashFunction: .sha256,
        cardAlgorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1)
      )
    }
  }

  /// Computes `H(UTF8(origin)) || H(UTF8(challengeNonce))` for domain separation
  /// between origin and nonce (`web-eid-app/authenticate.cpp`).
  public static func authenticationSignedPayload(
    origin: WebEidOrigin,
    challengeNonce: String,
    hashFunction: WebEidHashFunction
  ) -> Data? {
    guard
      let originHash = hashFunction.digest(Data(origin.value.utf8)),
      let nonceHash = hashFunction.digest(Data(challengeNonce.utf8))
    else {
      return nil
    }
    return originHash + nonceHash
  }

  /// Computes the final digest `H(H(origin) || H(challengeNonce))` passed to
  /// the smart card's authentication key.
  public static func authenticationDigest(
    origin: WebEidOrigin,
    challengeNonce: String,
    hashFunction: WebEidHashFunction
  ) -> Data? {
    guard
      let signedPayload = authenticationSignedPayload(
        origin: origin,
        challengeNonce: challengeNonce,
        hashFunction: hashFunction
      )
    else {
      return nil
    }
    return hashFunction.digest(signedPayload)
  }

  /// Advertised Web eID signing algorithms for `profile`.
  public static func supportedSigningAlgorithms(
    for profile: CardKeyProfile
  ) -> [WebEidSignatureAlgorithm] {
    let hashes: [WebEidHashFunction] = [.sha256, .sha384, .sha512]
    return hashes.map { hash in
      wireSignatureAlgorithm(for: profile, hashFunction: hash)
    }
  }

  /// Maps `profile` and `hashFunction` to the card signing algorithm and the
  /// Web eID `SignatureAlgorithm` descriptor.
  public static func signingParameters(
    for profile: CardKeyProfile,
    hashFunction: WebEidHashFunction
  ) -> (cardAlgorithm: SigningAlgorithm, wireAlgorithm: WebEidSignatureAlgorithm) {
    let scheme: SigningScheme =
      switch profile {
      case .ecdsaP256, .ecdsaP384:
        .ecdsa

      case .rsa2048, .rsa3072:
        .rsaPkcs1
      }
    return (
      cardAlgorithm: SigningAlgorithm(hash: hashFunction.signingHash, scheme: scheme),
      wireAlgorithm: wireSignatureAlgorithm(for: profile, hashFunction: hashFunction)
    )
  }

  /// Locally verifies a raw card signature over `digest` against `publicKey`
  /// before any signature leaves the app (fail-closed invariant).
  public static func verifyRawSignature(
    _ rawSignature: Data,
    overDigest digest: Data,
    hashFunction: WebEidHashFunction,
    profile: CardKeyProfile,
    publicKey: SecKey
  ) -> Bool {
    guard
      rawSignature.count == profile.rawSignatureLength,
      digest.count == hashFunction.digestByteCount
    else {
      return false
    }
    let verificationAlgorithm: SecKeyAlgorithm
    let verificationSignature: Data
    switch profile {
    case .ecdsaP256, .ecdsaP384:
      guard let der = EcdsaSignature.derFromRawConcatenation(rawSignature) else {
        return false
      }
      verificationAlgorithm = hashFunction.ecdsaDigestAlgorithm
      verificationSignature = der

    case .rsa2048, .rsa3072:
      verificationAlgorithm = hashFunction.rsaPkcs1DigestAlgorithm
      verificationSignature = rawSignature
    }
    return SecKeyVerifySignature(
      publicKey,
      verificationAlgorithm,
      digest as CFData,
      verificationSignature as CFData,
      nil
    )
  }

  /// Builds the `web-eid:1.0` authentication response payload using standard
  /// Base64 encoding for certificate and raw card signature bytes.
  public static func makeAuthenticationResponse(
    certificateDER: Data,
    jwsAlgorithm: String,
    rawSignature: Data,
    appVersion: String
  ) -> WebEidResponsePayload {
    .authenticate(
      WebEidResponsePayload.AuthenticationToken(
        unverifiedCertificate: certificateDER.base64EncodedString(),
        algorithm: jwsAlgorithm,
        signature: rawSignature.base64EncodedString(),
        format: WebEidValues.tokenFormat,
        appVersion: WebEidValues.appVersionPrefix + appVersion
      )
    )
  }

  private static func wireSignatureAlgorithm(
    for profile: CardKeyProfile,
    hashFunction: WebEidHashFunction
  ) -> WebEidSignatureAlgorithm {
    switch profile {
    case .ecdsaP256, .ecdsaP384:
      return WebEidSignatureAlgorithm(
        cryptoAlgorithm: WebEidValues.cryptoAlgorithmEcc,
        hashFunction: hashFunction.rawValue,
        paddingScheme: WebEidValues.paddingSchemeNone
      )

    case .rsa2048, .rsa3072:
      return WebEidSignatureAlgorithm(
        cryptoAlgorithm: WebEidValues.cryptoAlgorithmRsa,
        hashFunction: hashFunction.rawValue,
        paddingScheme: WebEidValues.paddingSchemePkcs1
      )
    }
  }
}
