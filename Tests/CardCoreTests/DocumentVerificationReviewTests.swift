// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Testing

  @testable import CardCore

  /// Path revocation, anchors, CMS strictness and timestamp states
  /// (RFC 5280 sections 5.3.1 and 6; RFC 5652 sections 5 and 11.1;
  /// RFC 6960 section 4.1.1; RFC 3161 section 2.4.2).
  @Suite
  internal struct DocumentVerificationReviewTests {
    /// Inside every certificate's validity and the evidence windows.
    internal static let currentTime = "20260601000000Z"

    /// Before the evidence's thisUpdate by more than the clock skew.
    private static let beforeEvidence = "20260401000000Z"

    /// A serial whose first octet has the high bit set.
    private static let highBitSerial = Data([UInt8.max, UInt8(ascii: "*")])

    /// A serial no certificate of the fixture carries.
    internal static let otherSerial = Data("o".utf8)

    /// id-ce-cRLReasons (RFC 5280 section 5.3.1).
    private static let reasonCodeOid = "2.5.29.21"

    /// CRLReason removeFromCRL (RFC 5280 section 5.3.1).
    private static let removeFromCrlCode = 8

    /// A CRLReason code RFC 5280 does not name.
    private static let unnamedReasonCode = 7

    /// Bytes that are no certificate.
    internal static var notACertificate: Data {
      DerEncoder.sequence([DerEncoder.integer(SignOids.cmsVersion)])
    }

    /// Text a timestamp imprints in the direct judge tests.
    internal static let stampedBytes = Data("time-stamped bytes".utf8)

    internal static func report(
      _ fixture: DocumentTrustFixture,
      _ contents: DocumentTrustFixture.Contents
    ) throws -> DocumentVerification.SignatureReport {
      try Self.report(fixture, contents, now: Self.currentTime)
    }

    internal static func report(
      _ fixture: DocumentTrustFixture,
      _ contents: DocumentTrustFixture.Contents,
      now: String
    ) throws -> DocumentVerification.SignatureReport {
      try DocumentTrustFixture.report(
        fixture.document(contents),
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(now)
      )
    }

    internal static func entries(
      _ fixture: DocumentTrustFixture,
      _ contents: DocumentTrustFixture.Contents
    ) throws -> DocumentVerification.DocumentReport {
      try DocumentVerification.verify(
        document: fixture.document(contents),
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
    }

    /// A good signer under an intermediate without evidence is
    /// unavailable, never good.
    @Test
    internal func intermediateWithoutEvidenceLeavesThePathUnavailable() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [fixture.revocationList(revoking: false)]
        )
      )

      #expect(report.revocation == .unavailable)
      #expect(report.pendingRevocationQueries.map(\.certificate) == [fixture.issuing])
    }

    /// Good answers for every certificate below the anchor make the
    /// path good; a revoked intermediate makes it revoked.
    @Test
    internal func everyCertificateBelowTheAnchorIsJudged() throws {
      let fixture = try DocumentTrustFixture()
      let good = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [
            fixture.revocationList(revoking: false), fixture.rootRevocationList(revoking: false),
          ]
        )
      )
      guard case .good = good.revocation else {
        Issue.record("The path was not good")
        return
      }
      #expect(good.pendingRevocationQueries.isEmpty)

      let revoked = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [
            fixture.revocationList(revoking: false), fixture.rootRevocationList(revoking: true),
          ]
        )
      )
      guard case .revoked = revoked.revocation else {
        Issue.record("The revoked intermediate was not found")
        return
      }
      #expect(!revoked.isValid)
    }

    /// A live answer covers an intermediate the document left
    /// unavailable, and its revocation counts.
    @Test
    internal func liveAnswerCoversTheIntermediate() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [fixture.revocationList(revoking: false)]
        )
      )
      let updated = report.withLiveRevocation(
        ocspResponses: [],
        revocationLists: [try fixture.rootRevocationList(revoking: true)],
        now: try DocumentTrustFixture.instant(Self.currentTime)
      )

      guard case .revoked = updated.revocation else {
        Issue.record("The live revocation of the intermediate was not applied")
        return
      }
      #expect(!updated.isValid)
    }

    /// A certificate with an anchor's subject and key but other bytes is
    /// not the anchor.
    @Test
    internal func lookalikeOfTheAnchorIsNotTheAnchor() throws {
      let fixture = try DocumentTrustFixture()
      let lookalike = try CertificateRevocationListFixtures.certificate(
        description: .init(
          allowsCrlSigning: true,
          includesKeyUsage: true,
          malformedKeyUsage: false,
          commonName: DocumentTrustFixture.rootName,
          isCertificateAuthority: true,
          issuerName: CertificateRevocationListFixtures.name(DocumentTrustFixture.rootName),
          serial: Self.otherSerial
        ),
        publicKey: fixture.rootKey, signer: fixture.rootKey, kind: fixture.kind
      )
      let path = CertificatePath.anchored(
        lookalike,
        candidates: [],
        anchors: [fixture.root],
        at: try DocumentTrustFixture.instant(Self.currentTime)
      )

      #expect(path != [lookalike])
      #expect(
        CertificatePath.anchored(
          fixture.root, candidates: [], anchors: [fixture.root],
          at: try DocumentTrustFixture.instant(Self.currentTime)) == [fixture.root])
    }

    /// A revoked serial whose first octet has the high bit set is found
    /// by CRL and by OCSP under either CertID hash.
    @Test
    internal func highBitSerialIsMatched() throws {
      let fixture = try DocumentTrustFixture(signerSerial: Self.highBitSerial)
      let revoked = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [fixture.revocationList(revoking: true)]
        )
      )
      guard case .revoked = revoked.revocation else {
        Issue.record("The high-bit serial was not found on the CRL")
        return
      }
      for hash in [DocumentTrustFixture.CertIdHash.sha1, .sha256] {
        let report = try Self.report(
          fixture,
          .init(
            cmsCertificates: [fixture.issuing],
            cmsRevocationLists: [fixture.rootRevocationList(revoking: false)],
            storeOcspResponses: [fixture.ocspResponse(certIdHash: hash)]
          )
        )
        guard case .good = report.revocation else {
          Issue.record("The high-bit serial was not matched by OCSP")
          return
        }
      }
    }

    /// A CertID naming another issuer name, issuer key or serial speaks
    /// for nothing.
    @Test(arguments: DocumentTrustFixture.CertIdMismatch.allCases)
    internal func certIdNamingSomethingElseIsIgnored(
      _ mismatch: DocumentTrustFixture.CertIdMismatch
    ) throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          storeOcspResponses: [fixture.ocspResponse(certIdHash: .sha256, mismatching: mismatch)]
        )
      )

      #expect(report.revocation == .unavailable)
    }

    /// An answer dated past the clock beyond the skew is ignored.
    @Test
    internal func postDatedAnswerIsIgnored() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          storeOcspResponses: [fixture.ocspResponse(certIdHash: .sha1)]
        ),
        now: Self.beforeEvidence
      )

      #expect(report.revocation == .unavailable)
    }

    /// A removeFromCRL entry revokes nothing; an unnamed reason code is
    /// a revocation judged by its time.
    @Test
    internal func reasonCodesAreRead() throws {
      let fixture = try DocumentTrustFixture()
      func list(code: Int) throws -> Data {
        var options = CertificateRevocationListFixtures.Options.standard
        options.listsTargetSerial = true
        options.revokedSerial = fixture.signerSerial
        options.entryExtensions = [
          CertificateRevocationListFixtures.extensionValue(
            oid: Self.reasonCodeOid,
            critical: false,
            value: DerEncoder.tlv(DerValues.tagEnumerated, Data([UInt8(code)]))
          )
        ]
        return try CertificateRevocationListFixtures.crl(
          issuerKey: fixture.issuingKey, kind: fixture.kind, options: options)
      }
      let removed = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [try list(code: Self.removeFromCrlCode)]
        )
      )
      guard case .good = RevocationJudge.combined(Array(removed.revocationLinks.prefix(1))) else {
        Issue.record("A removeFromCRL entry was read as a revocation")
        return
      }
      let unnamed = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [try list(code: Self.unnamedReasonCode)]
        )
      )
      guard case .revoked(_, let reason) = unnamed.revocation else {
        Issue.record("The unnamed reason was not a revocation")
        return
      }
      #expect(reason == .unrecognized)
    }

  }

#endif
