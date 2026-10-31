// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Hand-built PAdES signatures in the encodings another generator may
/// write, verified end to end.
extension QualifiedDocumentCmsTests {
  /// One foreign signature's choices.
  private struct ForeignForm {
    let profile: CardKeyProfile
    let digest: DocumentDigestAlgorithm
    let signerDigest: Data
    let signatureAlgorithm: Data
  }

  /// ecdsa-with-SHA256 or ecdsa-with-SHA384, parameters absent.
  private static func ecdsaIdentifier(_ oid: String) -> Data {
    DerEncoder.sequence([DerEncoder.objectIdentifier(oid)])
  }

  /// The report of one hand-built signature over a fresh document.
  private static func foreignReport(
    _ form: ForeignForm
  ) throws -> DocumentVerification.SignatureReport {
    let identity = try Self.identity(form.profile)
    let placeholder = try Self.placeholder()
    let attributes = Self.foreignSignedAttributes(
      form.digest,
      byteRangeDigest: placeholder.digest(form.digest),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: form.signerDigest,
        signatureDigest: form.digest,
        signatureAlgorithm: form.signatureAlgorithm
      ),
      attributes: attributes
    )
    return try Self.report(placeholder, cms: cms)
  }

  /// A SHA-384 signature with the explicit SHA-384 ESSCertIDv2 verifies
  /// for RSA and ECDSA.
  @Test(arguments: [CardKeyProfile.rsa3072, .ecdsaP384])
  internal func sha384ForeignSignatureVerifies(
    _ profile: CardKeyProfile
  ) throws {
    let signatureAlgorithm =
      profile == .rsa3072
      ? DocumentSignatureAlgorithm.rsaPkcs1(.sha384).algorithmIdentifier
      : Self.ecdsaIdentifier(SignOids.ecdsaWithSha384)
    let report = try Self.foreignReport(
      ForeignForm(
        profile: profile,
        digest: .sha384,
        signerDigest: Self.digestIdentifier(SignOids.sha384),
        signatureAlgorithm: signatureAlgorithm
      )
    )

    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  /// A digest AlgorithmIdentifier with NULL parameters is accepted
  /// (RFC 5754 section 2).
  @Test
  internal func nullDigestParametersAreAccepted() throws {
    let report = try Self.foreignReport(
      ForeignForm(
        profile: .rsa2048,
        digest: .sha256,
        signerDigest: DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.sha256), DerEncoder.null(),
        ]),
        signatureAlgorithm: Self.sha256WithRsa
      )
    )

    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  /// A signature algorithm naming another digest or another key type is
  /// refused, even over a correct signature.
  @Test(arguments: [
    Self.ecdsaIdentifier(SignOids.ecdsaWithSha384),
    DocumentSignatureAlgorithm.rsaPkcs1(.sha256).algorithmIdentifier,
  ])
  internal func disagreeingSignatureAlgorithmIsRefused(
    _ signatureAlgorithm: Data
  ) throws {
    let report = try Self.foreignReport(
      ForeignForm(
        profile: .ecdsaP256,
        digest: .sha256,
        signerDigest: Self.digestIdentifier(SignOids.sha256),
        signatureAlgorithm: signatureAlgorithm
      )
    )

    #expect(report.documentIntact)
    #expect(!report.signatureValid)
  }

  /// The agreeing ECDSA identifier and id-ecPublicKey both verify.
  @Test(arguments: [
    Self.ecdsaIdentifier(SignOids.ecdsaWithSha256),
    DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecPublicKey)]),
  ])
  internal func agreeingEcdsaSignatureAlgorithmVerifies(
    _ signatureAlgorithm: Data
  ) throws {
    let report = try Self.foreignReport(
      ForeignForm(
        profile: .ecdsaP256,
        digest: .sha256,
        signerDigest: Self.digestIdentifier(SignOids.sha256),
        signatureAlgorithm: signatureAlgorithm
      )
    )

    #expect(report.signatureValid)
  }

  /// An RSA signature algorithm with absent parameters verifies
  /// (RFC 5754 section 3.2).
  @Test(arguments: [DocumentDigestAlgorithm.sha256, .sha384])
  internal func rsaSignatureAlgorithmWithoutParametersVerifies(
    _ digest: DocumentDigestAlgorithm
  ) throws {
    let oid = digest == .sha256 ? SignOids.sha256WithRsa : SignOids.sha384WithRsa
    let report = try Self.foreignReport(
      ForeignForm(
        profile: .rsa2048,
        digest: digest,
        signerDigest: digest.algorithmIdentifier,
        signatureAlgorithm: DerEncoder.sequence([DerEncoder.objectIdentifier(oid)])
      )
    )

    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  /// ECDSA identifiers with NULL parameters are refused when read
  /// (RFC 5758 section 3.2).
  @Test
  internal func ecdsaSignatureAlgorithmWithNullIsRefused() {
    let encoded = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256), DerEncoder.null(),
    ])
    #expect(DocumentSignatureAlgorithm(algorithmIdentifier: encoded) == nil)
  }

  /// An unsupported signature algorithm is refused when read.
  @Test
  internal func unsupportedSignatureAlgorithmIsRefused() throws {
    let identity = try Self.identity(.rsa2048)
    let placeholder = try Self.placeholder()
    let attributes = Self.foreignSignedAttributes(
      .sha256,
      byteRangeDigest: placeholder.digest(.sha256),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: Self.digestIdentifier(SignOids.sha256),
        signatureDigest: .sha256,
        signatureAlgorithm: DerEncoder.sequence([
          DerEncoder.objectIdentifier(SignOids.sha512WithRsa), DerEncoder.null(),
        ])
      ),
      attributes: attributes
    )

    #expect(
      throws: QualifiedDocumentCms.ReadFailure.unsupportedSignatureAlgorithm
    ) {
      _ = try QualifiedDocumentCms.read(cms)
    }
  }
}
