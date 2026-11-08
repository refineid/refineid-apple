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
  }

#endif
