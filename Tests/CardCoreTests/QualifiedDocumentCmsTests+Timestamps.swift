// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Signature and document timestamps verified under each token's own
/// messageImprint hash algorithm (RFC 3161 section 2.4.2).
extension QualifiedDocumentCmsTests {
  /// Text whose digest is an imprint over bytes no signature carries.
  private static let unrelatedBytes = Data("not the signature value".utf8)

  /// The report of a SHA-256 RSA signature with one timestamp token.
  ///
  /// The token's imprint digests what `imprintOf` makes of the
  /// signature value.
  private static func timestampedReport(
    algorithm: DocumentDigestAlgorithm,
    imprintOf: (Data) -> Data
  ) throws -> DocumentVerification.SignatureReport {
    let identity = try Self.identity(.rsa2048)
    let authority = try TimestampAuthorityFixture.make()
    let placeholder = try Self.placeholder()
    let attributes = Self.sha256SignedAttributes(
      byteRangeDigest: placeholder.digest(.sha256),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: SignOids.sha256,
        signatureDigest: .sha256,
        signatureAlgorithm: Self.sha256WithRsa
      ),
      attributes: attributes
    ) { signature in
      [
        try authority.token(
          imprint: algorithm.hash(imprintOf(signature)), algorithm: algorithm
        )
      ]
    }
    return try Self.report(placeholder, cms: cms)
  }

  /// A signature timestamp over the signature value verifies whether
  /// its imprint is SHA-256 or SHA-384.
  @Test(arguments: [DocumentDigestAlgorithm.sha256, .sha384])
  internal func signatureTimestampVerifiesUnderItsImprintAlgorithm(
    _ algorithm: DocumentDigestAlgorithm
  ) throws {
    let report = try Self.timestampedReport(algorithm: algorithm) { $0 }

    #expect(report.documentIntact)
    #expect(report.signatureValid)
    #expect(report.timestampsValid)
    #expect(report.timestampedAt != nil)
  }

  /// A signature timestamp over other bytes does not verify.
  @Test(arguments: [DocumentDigestAlgorithm.sha256, .sha384])
  internal func signatureTimestampOverOtherBytesIsInvalid(
    _ algorithm: DocumentDigestAlgorithm
  ) throws {
    let report = try Self.timestampedReport(algorithm: algorithm) { _ in
      Self.unrelatedBytes
    }

    #expect(report.signatureValid)
    #expect(!report.timestampsValid)
    #expect(report.timestampedAt == nil)
  }

  /// A document timestamp verifies against the byte ranges digested
  /// under its own imprint algorithm, and not over other bytes.
  @Test(arguments: [DocumentDigestAlgorithm.sha256, .sha384])
  internal func documentTimestampVerifiesUnderItsImprintAlgorithm(
    _ algorithm: DocumentDigestAlgorithm
  ) throws {
    let identity = try Self.identity(.rsa2048)
    let authority = try TimestampAuthorityFixture.make()
    let placeholder = try Self.placeholder()
    let attributes = Self.sha256SignedAttributes(
      byteRangeDigest: placeholder.digest(.sha256),
      certificate: identity.certificate
    )
    let cms = try Self.contentInfo(
      ForeignCms(
        identity: identity,
        signerDigest: SignOids.sha256,
        signatureDigest: .sha256,
        signatureAlgorithm: Self.sha256WithRsa
      ),
      attributes: attributes
    )
    let signed = try placeholder.filled(with: cms)
    let revision = try PdfIncrementalSigner.prepare(
      signed, revision: .documentTimestamp
    )

    let matching = try revision.filled(
      with: authority.token(
        imprint: revision.digest(algorithm), algorithm: algorithm
      )
    )
    let unrelated = try revision.filled(
      with: authority.token(
        imprint: algorithm.hash(Self.unrelatedBytes), algorithm: algorithm
      )
    )

    let verified = try DocumentVerification.verify(document: matching)
    #expect(verified.documentTimestampedAt.count == 1)
    let refused = try DocumentVerification.verify(document: unrelated)
    #expect(refused.documentTimestampedAt.isEmpty)
  }
}
