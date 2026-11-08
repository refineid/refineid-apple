// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// A PDF's level asks only of its document security store: revocation
  /// values carried elsewhere answer the path but raise no level
  /// (EN 319 142-1 clause 6.3).
  @Suite
  internal struct SignatureLevelStoreTests {
    /// A first archive timestamp's clock, later than the second's.
    private static let laterArchiveTime = "20260525000000Z"

    /// The fixture's PDF whose CMS carries the path's CRLs and whose
    /// store holds only a CRL of another hierarchy, which answers
    /// nothing on this path.
    private static func unrelatedStorePdf(_ fixture: DocumentTrustFixture) throws -> Data {
      let other = try DocumentTrustFixture()
      return try fixture.document(
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: SignatureLevelTests.pathRevocationLists(fixture),
          storeRevocationLists: [other.revocationList(revoking: false)],
          timestampTimes: [SignatureLevelTests.signatureStampTime]
        ))
    }

    /// `document` with one more document timestamp, its clock at
    /// `generalizedTime`.
    private static func documentStamped(
      _ document: Data,
      _ fixture: DocumentTrustFixture,
      at generalizedTime: String
    ) throws -> Data {
      let revision = try PdfIncrementalSigner.prepare(document, revision: .documentTimestamp)
      let token = try fixture.authority.token(
        imprint: revision.digest(.sha384), generalizedTime: generalizedTime)
      return try revision.filled(with: token)
    }

    /// A store whose revocation values do not answer the path is not
    /// B-LT, though the CMS's own values answer it.
    @Test
    internal func storeThatDoesNotAnswerThePathIsNotLongTerm() throws {
      let fixture = try DocumentTrustFixture()
      let report = try SignatureLevelTests.anchoredReport(Self.unrelatedStorePdf(fixture), fixture)

      guard case .good = report.revocation else {
        Issue.record("The CMS's values did not answer the path")
        return
      }
      #expect(report.isValid)
      #expect(report.level == .timestamped)
    }

    /// A document timestamp over a store that does not answer the path
    /// archives nothing.
    @Test
    internal func documentTimestampOverAStoreThatDoesNotAnswerIsNoArchive() throws {
      let fixture = try DocumentTrustFixture()
      let stamped = try SignatureLevelTests.documentStamped(
        Self.unrelatedStorePdf(fixture), fixture)

      let report = try SignatureLevelTests.anchoredReport(stamped, fixture)
      #expect(report.archiveTimestamps.isEmpty)
      #expect(report.level == .timestamped)
    }

    /// A PDF carrying only a document timestamp has no signature.
    @Test
    internal func documentTimestampAloneIsNoSignature() throws {
      let fixture = try DocumentTrustFixture()
      let stamped = try SignatureLevelTests.documentStamped(
        PdfIncrementalSignerTests.minimalPdf, fixture)

      #expect(throws: DocumentVerification.Failure.noSignatures) {
        try DocumentVerification.verify(
          document: stamped, anchors: fixture.anchors(anchorsAuthority: true),
          now: SignatureLevelTests.now())
      }
    }

    /// Two archive document timestamps are reported in document order,
    /// the one added last last, though its clock names an earlier time.
    @Test
    internal func archiveDocumentTimestampsAreInDocumentOrder() throws {
      let fixture = try DocumentTrustFixture()
      let longTerm = try SignatureLevelTests.pdf(fixture, timestamped: true, stored: true)
      let first = try Self.documentStamped(longTerm, fixture, at: Self.laterArchiveTime)
      let both = try Self.documentStamped(first, fixture, at: SignatureLevelTests.archiveStampTime)

      let report = try SignatureLevelTests.anchoredReport(both, fixture)
      #expect(
        report.archiveTimestamps == [
          .anchored(try DocumentTrustFixture.instant(Self.laterArchiveTime)),
          .anchored(try DocumentTrustFixture.instant(SignatureLevelTests.archiveStampTime)),
        ])
      #expect(report.level == .longTermArchival)
    }
  }

#endif
