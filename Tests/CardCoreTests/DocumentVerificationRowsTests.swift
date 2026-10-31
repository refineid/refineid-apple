// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Every signature dictionary and document timestamp is a row
  /// (EN 319 102-1 clause 5.4; ISO 32000-1 clause 12.8).
  @Suite
  internal struct DocumentVerificationRowsTests {
    /// A subfilter this verifier does not judge, padded to the length
    /// of the one the signer writes.
    private static let otherSubFilter = "/adbe.x509.rsa_sha1 "

    /// Inside every certificate's validity.
    private static let currentTime = "20260601000000Z"

    /// The document timestamp's generation time.
    private static let documentStampTime = "20260520000000Z"

    /// A DER value that is no RFC 3161 token.
    private static var notAToken: Data {
      DerEncoder.sequence([DerEncoder.integer(SignOids.cmsVersion)])
    }

    /// The fixture's document with a second signature revision whose
    /// subfilter is `otherSubFilter`.
    private static func twoSignatures(_ fixture: DocumentTrustFixture) throws -> Data {
      let contents = DocumentTrustFixture.Contents(cmsCertificates: [fixture.issuing])
      let first = try fixture.document(contents)
      let prepared = try PdfIncrementalSigner.prepare(
        first,
        revision: .signature(
          PdfIncrementalSigner.SignatureClaim(
            signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil)
        )
      )
      let edited = try DocumentTrustFixture.replacingSubFilter(
        in: prepared, with: Self.otherSubFilter, after: first.count)
      return try edited.filled(with: fixture.cms(over: edited, contents))
    }

    /// One supported and one unsupported signature yield two rows, the
    /// second unsupported, and the document is not valid.
    @Test
    internal func unsupportedSignatureIsARowAndBlocksTheDocument() throws {
      let fixture = try DocumentTrustFixture()
      let report = try DocumentVerification.verify(
        document: Self.twoSignatures(fixture),
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )

      try #require(report.signatures.count == 2)
      guard
        case .judged(let first) = report.signatures[0],
        case .unsupported = report.signatures[1]
      else {
        Issue.record("The rows were not one judged and one unsupported")
        return
      }
      #expect(first.isValid)
      #expect(!report.isValid)
    }

    /// A document timestamp whose token does not verify is a row marked
    /// not valid.
    @Test
    internal func corruptDocumentTimestampIsAnInvalidRow() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(.init(cmsCertificates: [fixture.issuing]))
      let revision = try PdfIncrementalSigner.prepare(signed, revision: .documentTimestamp)
      let stamped = try revision.filled(with: Self.notAToken)

      let report = try DocumentVerification.verify(
        document: stamped,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )

      #expect(report.documentTimestamps == [.unsupported])
      #expect(report.signatures.count == 1)
      // A failed document timestamp decides nothing (EN 319 102-1
      // clause 5.4): the signature below it keeps the verdict.
      #expect(report.isValid)
    }

    /// An anchored document timestamp over a signature's revision is
    /// that signature's proof of existence.
    @Test
    internal func anchoredDocumentTimestampProvesTheSignatureBelowIt() throws {
      let fixture = try DocumentTrustFixture()
      let signed = try fixture.document(.init(cmsCertificates: [fixture.issuing]))
      let revision = try PdfIncrementalSigner.prepare(signed, revision: .documentTimestamp)
      let token = try fixture.authority.token(
        imprint: revision.digest(.sha384), generalizedTime: Self.documentStampTime
      )
      let stamped = try revision.filled(with: token)
      let stampTime = try DocumentTrustFixture.instant(Self.documentStampTime)

      let report = try DocumentVerification.verify(
        document: stamped,
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )

      #expect(report.documentTimestamps == [.anchored(stampTime)])
      guard case .judged(let signature) = report.signatures.first else {
        Issue.record("The signature was not judged")
        return
      }
      #expect(signature.proofOfExistence == stampTime)
      #expect(signature.timestamps.isEmpty)

      let unanchored = try DocumentVerification.verify(
        document: stamped,
        anchors: fixture.anchors(anchorsAuthority: false),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
      #expect(unanchored.documentTimestamps == [.claimed(stampTime)])
      #expect(unanchored.judged.first?.proofOfExistence == nil)
    }
  }

#endif
