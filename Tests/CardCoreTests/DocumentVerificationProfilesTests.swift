// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// Third-party signature profiles, keys and evidence (EN 319 142-2
  /// clause 4.2.3; EN 319 132-1 clause 5.2.2; RFC 6960 section 4.1.1).
  @Suite
  internal struct DocumentVerificationProfilesTests {
    /// Inside every certificate's validity and the evidence windows.
    private static let currentTime = "20260601000000Z"

    /// The PKCS #7 detached subfilter (EN 319 142-2 clause 4.2.3 c).
    private static let pkcs7SubFilter = "/adbe.pkcs7.detached"

    /// An RSA modulus larger than any card key.
    private static let largeRsaBits = 4_096

    private static func report(
      _ fixture: DocumentTrustFixture,
      _ contents: DocumentTrustFixture.Contents
    ) throws -> DocumentVerification.SignatureReport {
      try DocumentTrustFixture.report(
        fixture.document(contents),
        anchors: fixture.anchors(anchorsAuthority: true),
        now: DocumentTrustFixture.instant(Self.currentTime)
      )
    }

    /// A PKCS #7 detached signature without the ESS binding is judged
    /// and valid.
    @Test
    internal func pkcs7DetachedWithoutBindingIsJudgedValid() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          omitsSigningCertificate: true,
          carriesSigningTime: true,
          subFilter: Self.pkcs7SubFilter
        )
      )

      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(report.chainVerified)
      #expect(report.isValid)
    }

    /// A PAdES baseline signature without the ESS binding is not valid.
    @Test
    internal func cadesDetachedWithoutBindingIsNotValid() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture, .init(cmsCertificates: [fixture.issuing], omitsSigningCertificate: true))

      #expect(report.documentIntact)
      #expect(!report.signatureValid)
      #expect(!report.isValid)
    }

    /// A PAdES baseline signature carrying signing-time is not valid.
    @Test
    internal func cadesDetachedWithSigningTimeIsNotValid() throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture, .init(cmsCertificates: [fixture.issuing], carriesSigningTime: true))

      #expect(!report.signatureValid)
    }

    /// A PDF signer with an RSA key larger than any card key is judged.
    @Test
    internal func largeRsaPdfSignerIsJudged() throws {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.largeRsaBits)
      let report = try Self.report(fixture, .init(cmsCertificates: [fixture.issuing]))

      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(report.chainVerified)
      #expect(report.isValid)
    }

    /// A XAdES signer with an RSA key larger than any card key is judged.
    @Test
    internal func largeRsaXadesSignerIsJudged() throws {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.largeRsaBits)
      // The writer takes a card profile only to name its RSA
      // SignatureMethod; the key itself is the fixture's 4096-bit one.
      let identity = QualifiedDocumentCmsTests.Identity(
        certificate: fixture.signer.certificate,
        privateKey: fixture.signer.privateKey,
        profile: .rsa3072
      )
      let plan = try #require(
        XadesSignature.plan(
          objects: AsicVerificationTests.sampleObjects(),
          certificate: identity.certificate,
          profile: identity.profile,
          signedAt: AsicVerificationTests.signedAt
        )
      )
      let signature = try AsicVerificationTests.xmlSignature(
        over: plan.signedInfo, identity: identity, profile: identity.profile)
      let document = plan.document(
        xmlSignature: signature,
        timestampTokens: [],
        material: PdfValidationStore.Material(
          certificates: [fixture.issuing], ocspResponses: [], revocationLists: [])
      )
      let container = try AsicVerificationTests.container(
        document: try #require(String(data: document, encoding: .utf8)))
      let report = try #require(
        DocumentVerification.verify(
          document: container,
          anchors: fixture.anchors(anchorsAuthority: true),
          now: DocumentTrustFixture.instant(Self.currentTime)
        ).judged.first)

      #expect(report.documentIntact)
      #expect(report.signatureValid)
    }

    /// OCSP answers whose CertID hashes the issuer under SHA-256 or
    /// SHA-1 both speak for the signer, dated at producedAt.
    @Test(arguments: [DocumentTrustFixture.CertIdHash.sha1, .sha256])
    internal func ocspCertIdUnderEitherHashMatches(
      _ hash: DocumentTrustFixture.CertIdHash
    ) throws {
      let fixture = try DocumentTrustFixture()
      let report = try Self.report(
        fixture,
        .init(
          cmsCertificates: [fixture.issuing],
          storeRevocationLists: [fixture.rootRevocationList(revoking: false)],
          storeOcspResponses: [fixture.ocspResponse(certIdHash: hash)]
        )
      )

      #expect(
        report.revocation
          == .good(try DocumentTrustFixture.instant(DocumentTrustFixture.ocspProducedAt)))
    }
  }

#endif
