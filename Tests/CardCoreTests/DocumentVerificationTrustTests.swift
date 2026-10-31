// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Chain building, revocation and time-stamp anchoring of PAdES
  /// signatures (EN 319 102-1 clauses 5.2.6, 5.4 and 5.6.2).
  @Suite
  internal struct DocumentVerificationTrustTests {
    /// Inside every certificate's validity and the CRL fixtures' window.
    private static let currentTime = "20260601000000Z"

    /// After every certificate of the hierarchy has expired.
    private static let afterExpiry = "20310101000000Z"

    /// Before the CRL fixtures' revocation date.
    private static let beforeRevocation = "20260401000000Z"

    /// After the CRL fixtures' revocation date.
    private static let afterRevocation = "20260515000000Z"

    /// The CRL fixtures' thisUpdate.
    private static let listIssuedAt = "20260501000000Z"

    private static func report(
      _ fixture: DocumentTrustFixture,
      _ contents: DocumentTrustFixture.Contents,
      anchorsAuthority: Bool = true,
      now: String = Self.currentTime
    ) throws -> DocumentVerification.SignatureReport {
      try DocumentTrustFixture.report(
        fixture.document(contents),
        anchors: fixture.anchors(anchorsAuthority: anchorsAuthority),
        now: DocumentTrustFixture.instant(now)
      )
    }

    /// An issuing CA carried only in the CMS certificates chains the
    /// signer to the anchored root.
    @Test
    internal func issuerInsideTheCmsChainsToTheRoot() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(fixture, .init(cmsCertificates: [fixture.issuing]))

      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(report.chainVerified)
      #expect(report.issuerCertificate == fixture.issuing)
      #expect(report.signerCommonName == DocumentTrustFixture.signerCommonName)
      #expect(report.isValid)
    }

    /// An issuing CA carried only in the document security store
    /// chains the signer to the anchored root.
    @Test
    internal func issuerInsideTheStoreChainsToTheRoot() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(fixture, .init(storeCertificates: [fixture.issuing]))

      #expect(report.chainVerified)
      #expect(report.issuerCertificate == fixture.issuing)
    }

    /// Without its issuing CA anywhere the signer stays unverified.
    @Test
    internal func signerWithoutAnIssuerStaysUnverified() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(fixture, .init())

      #expect(report.signatureValid)
      #expect(!report.chainVerified)
      #expect(!report.isValid)
    }

    /// A chain to a root that is not an anchor is not verified.
    @Test
    internal func chainToAnUnanchoredRootIsNotVerified() throws {
      let fixture = try DocumentTrustFixture()
      let document = try fixture.document(
        .init(cmsCertificates: [fixture.issuing, fixture.root]))
      let report = try DocumentTrustFixture.report(
        document,
        anchors: TrustAnchors(certificateIssuing: [], timeStamping: []),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )

      #expect(!report.chainVerified)
    }

    /// A signature with no timestamp under a valid, unrevoked
    /// certificate is valid at the current time.
    @Test
    internal func untimestampedSignatureIsJudgedAtTheCurrentTime() throws {
      let fixture = try DocumentTrustFixture()
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let report = try Self.report(fixture, .init(cmsCertificates: [fixture.issuing]))

      #expect(report.timestamps.isEmpty)
      #expect(report.proofOfExistence == nil)
      #expect(report.validationTime == .currentClock(now))
      #expect(report.isValid)
    }

    /// The same signature after its certificate expired is not valid.
    @Test
    internal func untimestampedSignatureAfterExpiryIsNotValid() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture, .init(cmsCertificates: [fixture.issuing]), now: Self.afterExpiry)

      #expect(!report.chainVerified)
      #expect(!report.isValid)
    }

    /// An anchored timestamp proves its time and moves the validation
    /// time, so an expired certificate is judged while it was valid.
    @Test
    internal func anchoredTimestampProvesItsTime() throws {
      let fixture = try DocumentTrustFixture()
      let stamped = try DocumentTrustFixture.instant(Self.beforeRevocation)
      let report = try Self.report(
        fixture,
        .init(cmsCertificates: [fixture.issuing], timestampTimes: [Self.beforeRevocation]),
        now: Self.afterExpiry
      )

      #expect(report.timestamps == [.anchored(stamped)])
      #expect(report.proofOfExistence == stamped)
      #expect(report.validationTime.date == stamped)
      #expect(report.chainVerified)
      #expect(report.isValid)
    }

    /// A timestamp whose authority is not anchored is claimed, proves
    /// nothing, and leaves the signature judged at the current time.
    @Test
    internal func unanchoredTimestampIsClaimedAndMovesNothing() throws {
      let fixture = try DocumentTrustFixture()
      let stamped = try DocumentTrustFixture.instant(Self.beforeRevocation)
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let report = try Self.report(
        fixture,
        .init(cmsCertificates: [fixture.issuing], timestampTimes: [Self.beforeRevocation]),
        anchorsAuthority: false
      )

      #expect(report.timestamps == [.claimed(stamped)])
      #expect(report.claimedTime == stamped)
      #expect(report.proofOfExistence == nil)
      #expect(report.validationTime == .currentClock(now))
      #expect(report.isValid)
    }

    /// A self-made timestamp dated before a revocation does not save a
    /// revoked signer: it is unanchored, so the revocation counts.
    @Test
    internal func unanchoredTimestampDoesNotHideARevocation() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [fixture.revocationList(revoking: true)],
          timestampTimes: [Self.beforeRevocation]
        ),
        anchorsAuthority: false
      )

      guard case .revoked = report.revocation else {
        Issue.record("The revocation was not found")
        return
      }
      #expect(!report.isValid)
    }

    /// A revocation after the proof of existence leaves the signature
    /// valid.
    @Test
    internal func revocationAfterTheProofOfExistenceKeepsTheSignatureValid() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [fixture.revocationList(revoking: true)],
          timestampTimes: [Self.beforeRevocation]
        )
      )

      #expect(
        report.revocation == .revoked(try DocumentTrustFixture.instant(Self.listIssuedAt), nil))
      #expect(report.isValid)
    }

    /// A revocation before the proof of existence makes the signature
    /// not valid.
    @Test
    internal func revocationBeforeTheProofOfExistenceInvalidates() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          storeRevocationLists: [fixture.revocationList(revoking: true)],
          timestampTimes: [Self.afterRevocation]
        )
      )

      guard case .revoked = report.revocation else {
        Issue.record("The revocation was not found")
        return
      }
      #expect(!report.isValid)
    }

    /// Without a proof of existence any revocation counts.
    @Test
    internal func revocationWithoutProofOfExistenceInvalidates() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: [fixture.revocationList(revoking: true)]
        )
      )

      #expect(!report.isValid)
    }

    /// A good answer is dated at the evidence, not at the check.
    @Test
    internal func goodAnswerCarriesTheEvidenceTime() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          storeRevocationLists: [
            fixture.revocationList(revoking: false), fixture.rootRevocationList(revoking: false),
          ]
        )
      )

      #expect(report.revocation == .good(try DocumentTrustFixture.instant(Self.listIssuedAt)))
      #expect(report.isValid)
    }

    /// A compromise invalidates whatever the proof of existence.
    @Test
    internal func compromiseInvalidatesWhateverTheProof() throws {
      let revokedAt = try DocumentTrustFixture.instant(Self.afterRevocation)
      let proof = try DocumentTrustFixture.instant(Self.beforeRevocation)

      #expect(
        RevocationState.revoked(revokedAt, .keyCompromise).invalidates(proofOfExistence: proof))
      #expect(!RevocationState.revoked(revokedAt, .superseded).invalidates(proofOfExistence: proof))
      #expect(RevocationState.revoked(revokedAt, nil).invalidates(proofOfExistence: nil))
    }

    /// An OCSP answer in the document security store is used offline,
    /// dated at its producedAt.
    @Test
    internal func storedOcspAnswerIsUsedWithoutNetwork() throws {
      let document = try PdfValidationStore.appended(
        to: PdfIncrementalSignerTests.minimalPdf,
        material: PdfValidationStore.Material(
          certificates: [],
          ocspResponses: [OcspResponseTests.responseWithNextUpdate],
          revocationLists: []
        )
      )
      var evidence = ValidationEvidence()
      evidence.add(PdfDocumentSecurityStore.material(in: document))
      #expect(evidence.ocspResponses == [OcspResponseTests.responseWithNextUpdate])

      let status = RevocationJudge.status(
        of: OcspResponseTests.certificate,
        issuer: OcspResponseTests.issuerCertificate,
        evidence: evidence,
        at: OcspResponseTests.currentTime,
        now: OcspResponseTests.currentTime
      )
      guard case .good(let evidenceTime) = status else {
        Issue.record("The stored answer was not used")
        return
      }
      #expect(evidenceTime <= OcspResponseTests.currentTime)
    }

    /// A live answer applies only to a verified chain whose status the
    /// document left unavailable, and is judged at the time given.
    @Test
    internal func liveRevocationAppliesToAVerifiedChain() throws {
      let fixture = try DocumentTrustFixture()
      let now = try DocumentTrustFixture.instant(Self.currentTime)
      let report = try Self.report(fixture, .init(cmsCertificates: [fixture.issuing]))
      #expect(report.revocation == .unavailable)

      let revoked = report.withLiveRevocation(
        ocspResponses: [],
        revocationLists: [try fixture.revocationList(revoking: true)],
        now: now
      )
      guard case .revoked = revoked.revocation else {
        Issue.record("The live answer was not applied")
        return
      }
      #expect(!revoked.isValid)

      let unverified = try Self.report(fixture, .init())
      let untouched = unverified.withLiveRevocation(
        ocspResponses: [],
        revocationLists: [try fixture.revocationList(revoking: true)],
        now: now
      )
      #expect(untouched.revocation == .unavailable)
    }
  }

#endif
