// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Cryptographically verifies an RFC 3161 TimeStampToken.
///
/// The portable CMS verifier authenticates the signed attributes,
/// content digest, SignerIdentifier and signature. The remaining RFC 3161
/// rules are checked explicitly: one signer, ESS certificate binding, the
/// critical timestamping-only EKU, certificate validity at genTime,
/// and a path ending at one of the caller's trusted certificates.
public enum TimestampTokenVerifier {
  /// A token whose signature and timestamp signer were verified.
  public struct VerifiedToken: Equatable {
    /// The token exactly as received.
    public let token: Data

    /// The certificate selected by the CMS SignerIdentifier.
    public let signerCertificate: Data

    /// Every certificate embedded in SignedData.
    public let embeddedCertificates: [Data]

    /// The exact certificate path Security authenticated under the
    /// exclusive anchors in force for the verification.
    public let verifiedCertificateChain: [Data]

    /// The anchor certificate that terminated the authenticated path.
    public let trustedCertificate: Data

    /// The signed TSTInfo generation time.
    public let generatedAt: Date
  }

  /// Why a token could not be authenticated.
  public enum Failure: Error, Equatable {
    /// CMS signed-attribute, digest, or signature verification failed.
    case invalidSignature

    /// The signer certificate is not restricted to timestamping by
    /// one critical extended-key-usage extension.
    case invalidTimestampingCertificate

    /// The CMS or its encapsulated content is malformed or ambiguous.
    case malformed

    /// No embedded certificate matches the CMS SignerIdentifier.
    case signerCertificateMissing

    /// The signed ESS certificate reference does not identify the
    /// CMS signer certificate.
    case signingCertificateMismatch

    /// The signer did not build to one of the supplied trust
    /// certificates at the token's generation time.
    case untrustedSigner
  }

  /// Verifies `token` against the certificate chain it itself
  /// carries.
  ///
  /// The authority is trusted as configured: the caller decided whom
  /// to ask, so the token's own certificate set is the anchor set.
  /// Self-issued embedded certificates are preferred as anchors, so
  /// the verified path runs as deep as the token allows.
  public static func verify(_ token: Data) throws -> VerifiedToken {
    try Self.verify(token, trustedCertificates: Self.selfAnchors(in: token))
  }

  /// Verifies `token` under the supplied certificates.
  ///
  /// The trusted certificates are exclusive anchors. Passing an
  /// empty array fails closed; it never falls back to the system
  /// root store. `additionalCertificates` join the token's own
  /// certificates as path candidates and never become anchors.
  public static func verify(
    _ token: Data,
    trustedCertificates: [Data],
    additionalCertificates: [Data] = []
  ) throws -> VerifiedToken {
    let contents: RfcTimestamp.TokenContents
    do {
      contents = try RfcTimestamp.contents(in: token)
    } catch {
      throw Failure.malformed
    }

    let authenticated = try TimestampCmsVerifier.authenticate(
      token: token,
      expectedContent: contents.tstInfo,
      additionalCertificates: additionalCertificates
    )
    try Self.verifyCertificateBinding(
      token: token, certificate: authenticated.signerCertificate
    )
    guard
      Self.signerCertificateIsValid(
        authenticated.signerCertificate, at: contents.generatedAt
      )
    else {
      throw Failure.invalidTimestampingCertificate
    }
    let verifiedChain = try Self.evaluate(
      authenticated.trust,
      trustedCertificates: trustedCertificates,
      at: contents.generatedAt
    )
    guard let trustedCertificate = verifiedChain.last else {
      throw Failure.untrustedSigner
    }

    return VerifiedToken(
      token: token,
      signerCertificate: authenticated.signerCertificate,
      embeddedCertificates: authenticated.embeddedCertificates,
      verifiedCertificateChain: verifiedChain,
      trustedCertificate: trustedCertificate,
      generatedAt: contents.generatedAt
    )
  }

  /// The token's own anchor candidates: its self-issued embedded
  /// certificates, or every embedded certificate when none is.
  private static func selfAnchors(in token: Data) throws -> [Data] {
    let embedded = CmsCertificates.inside(token)
    guard !embedded.isEmpty else { throw Failure.malformed }
    let selfIssued = embedded.filter(Self.isSelfIssued)
    return selfIssued.isEmpty ? embedded : selfIssued
  }

  /// Whether a certificate names itself as its issuer.
  private static func isSelfIssued(_ certificate: Data) -> Bool {
    guard
      let parsed = SecCertificateCreateWithData(nil, certificate as CFData),
      let subject = SecCertificateCopyNormalizedSubjectSequence(parsed),
      let issuer = SecCertificateCopyNormalizedIssuerSequence(parsed)
    else { return false }
    return (subject as Data) == (issuer as Data)
  }

  /// ESS hash binding and the RFC 3161 timestamping-only EKU.
  private static func verifyCertificateBinding(
    token: Data,
    certificate: Data
  ) throws {
    do {
      try CmsSigningCertificate.verify(
        token: token, certificate: certificate
      )
    } catch {
      throw Failure.signingCertificateMismatch
    }
    guard
      Self.signerCertificateProfileIsValid(certificate)
    else {
      throw Failure.invalidTimestampingCertificate
    }
  }

  /// Timestamp signer profile checks that must hold even when the leaf is
  /// itself an exclusive caller-supplied trust anchor.
  internal static func signerCertificateProfileIsValid(
    _ certificate: Data
  ) -> Bool {
    CertificateFacts(der: certificate)?.isPermittedTimestampSigner == true
  }

  /// Verifies the signer's own X.509 validity interval at the signed
  /// TSTInfo generation time, not at the device's current wall clock.
  internal static func signerCertificateIsValid(
    _ certificate: Data,
    at generatedAt: Date
  ) -> Bool {
    guard
      let signer = SecCertificateCreateWithData(nil, certificate as CFData),
      let validity = CertificateValidity.window(of: signer)
    else { return false }
    return validity.notBefore <= generatedAt && generatedAt <= validity.notAfter
  }

  /// Evaluates signer trust at genTime under exclusive caller anchors.
  private static func evaluate(
    _ trust: SecTrust,
    trustedCertificates: [Data],
    at generatedAt: Date
  ) throws -> [Data] {
    let anchors = trustedCertificates.compactMap { encoded in
      SecCertificateCreateWithData(nil, encoded as CFData)
    }
    guard !anchors.isEmpty, anchors.count == trustedCertificates.count else {
      throw Failure.untrustedSigner
    }
    guard
      SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
      SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
      SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
      SecTrustSetVerifyDate(trust, generatedAt as CFDate) == errSecSuccess
    else {
      throw Failure.untrustedSigner
    }
    var trustError: CFError?
    guard SecTrustEvaluateWithError(trust, &trustError) else {
      throw Failure.untrustedSigner
    }
    guard
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
    else {
      throw Failure.untrustedSigner
    }
    let encoded = chain.map { SecCertificateCopyData($0) as Data }
    guard
      let terminal = encoded.last,
      trustedCertificates.contains(terminal)
    else {
      throw Failure.untrustedSigner
    }
    return encoded
  }
}
