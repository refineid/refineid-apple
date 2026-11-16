// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// Verifies end-to-end PDF verification enforcement of signer and subordinate-CA key usages.
  @Suite
  internal struct DocumentSignerEndToEndTests {
    /// Fixed validation instant within the synthetic hierarchy's validity window.
    private static let validationInstant = Date(timeIntervalSince1970: 1_780_272_000)

    /// Positive serial used for custom subordinate CAs.
    private static let subordinateCaSerial = Data([0x2A])

    /// Builds an unrevoked CRL signed by `issuerKey` for `commonName`.
    private static func unrevokedCrl(
      issuerKey: SecKey,
      commonName: String,
      kind: CertificateRevocationListFixtures.SignatureKind
    ) throws -> Data {
      try CertificateRevocationListFixtures.crl(
        issuerKey: issuerKey,
        kind: kind,
        options: .init(
          crlExtensions: [],
          crlIssuerCommonName: commonName,
          entryExtensions: [],
          includesNextUpdate: true,
          listsTargetSerial: false,
          nextUpdate: "20260615000000Z",
          thisUpdate: "20260515000000Z"
        )
      )
    }

    /// Signs a minimal PAdES PDF with `leaf` and `leafKey`, chaining through `intermediate`.
    private static func verifySignedPdf(
      fixture: DocumentTrustFixture,
      intermediate: Data,
      intermediateKey: SecKey,
      leaf: Data,
      leafKey: SecKey
    ) throws -> (
      document: DocumentVerification.DocumentReport, signature: DocumentVerification.SignatureReport
    ) {
      let placeholder = try QualifiedDocumentCmsTests.placeholder()
      let attributes = QualifiedDocumentCms.signedAttributes(
        byteRangeDigest: placeholder.digest(QualifiedDocumentCms.signingDigestAlgorithm),
        signerCertificate: leaf
      )
      let identity = QualifiedDocumentCmsTests.Identity(
        certificate: leaf, privateKey: leafKey, profile: .ecdsaP256
      )
      let cms = try QualifiedDocumentCms.assemble(
        signedAttributesSet: attributes,
        signatureValue: try QualifiedDocumentCmsTests.signature(
          over: attributes, identity: identity),
        signerProfile: .ecdsaP256,
        signerCertificate: leaf,
        timestampTokens: []
      )
      let rootCrl = try Self.unrevokedCrl(
        issuerKey: fixture.rootKey, commonName: DocumentTrustFixture.rootName, kind: fixture.kind
      )
      let intermediateCrl = try Self.unrevokedCrl(
        issuerKey: intermediateKey,
        commonName: CertificateRevocationListFixtures.issuerCommonName,
        kind: fixture.kind
      )
      let ltvPdf = try PdfValidationStore.appended(
        to: try placeholder.filled(with: cms),
        material: .init(
          certificates: [intermediate], ocspResponses: [],
          revocationLists: [rootCrl, intermediateCrl]
        )
      )
      let report = try DocumentVerification.verify(
        document: ltvPdf, anchors: fixture.anchors(anchorsAuthority: false),
        now: Self.validationInstant
      )
      try #require(report.signatures.count == 1)
      guard case .judged(let signature) = report.signatures[0] else {
        Issue.record("Expected judged signature report")
        throw CertificateRevocationListFixtures.FixtureFailure.signatureCreation
      }
      return (report, signature)
    }

    /// Generates a signer leaf issued under `CertificateRevocationListFixtures.issuerCommonName`.
    private static func signerLeaf(
      fixture: DocumentTrustFixture,
      leafKey: SecKey,
      signerKey: SecKey,
      includesKeyUsage: Bool = true,
      customKeyUsageContent: Data? = nil,
      additionalExtensions: [Data] = []
    ) throws -> Data {
      try CertificateRevocationListFixtures.certificate(
        description: .init(
          allowsCrlSigning: false,
          includesKeyUsage: includesKeyUsage,
          malformedKeyUsage: false,
          commonName: DocumentTrustFixture.signerCommonName,
          isCertificateAuthority: false,
          issuerName: CertificateRevocationListFixtures.name(
            CertificateRevocationListFixtures.issuerCommonName
          ),
          serial: fixture.signerSerial,
          customKeyUsageContent: customKeyUsageContent,
          additionalExtensions: additionalExtensions
        ),
        publicKey: leafKey,
        signer: signerKey,
        kind: fixture.kind
      )
    }

    /// End-to-end PDF verification accepts commitment signers carrying critical documentSigning EKU.
    @Test
    internal func acceptsCommitmentSignerWithCriticalDocumentSigningEku() throws {
      let fixture = try DocumentTrustFixture()
      let leafKey = try CertificateRevocationListFixtures.makeKey(for: fixture.kind)
      let validLeaf = try Self.signerLeaf(
        fixture: fixture,
        leafKey: leafKey,
        signerKey: fixture.issuingKey,
        customKeyUsageContent: DocumentSignerEligibilityTests.contentCommitmentKeyUsage,
        additionalExtensions: [
          DocumentSignerEligibilityTests.extendedKeyUsageExtension(
            oids: [SignOids.documentSigning], critical: true
          )
        ]
      )
      let accepted = try Self.verifySignedPdf(
        fixture: fixture, intermediate: fixture.issuing, intermediateKey: fixture.issuingKey,
        leaf: validLeaf, leafKey: leafKey
      )
      #expect(accepted.document.isValid)
      #expect(accepted.signature.chain.isAnchored)
    }

    /// End-to-end PDF verification rejects signers missing signing KeyUsage or restricted by critical EKU.
    @Test
    internal func rejectsNonSigningKeyUsageAndIncompatibleCriticalEku() throws {
      let fixture = try DocumentTrustFixture()
      let leafKey = try CertificateRevocationListFixtures.makeKey(for: fixture.kind)
      var rejectedLeaves = try [
        Self.signerLeaf(
          fixture: fixture, leafKey: leafKey, signerKey: fixture.issuingKey, includesKeyUsage: false
        ),
        Self.signerLeaf(
          fixture: fixture, leafKey: leafKey, signerKey: fixture.issuingKey,
          customKeyUsageContent: DocumentSignerEligibilityTests.keyEnciphermentOnlyKeyUsage
        ),
      ]
      for oid in [
        SignOids.serverAuthentication, SignOids.ocspSigning, SignOids.timestampingKeyPurpose,
      ] {
        rejectedLeaves.append(
          try Self.signerLeaf(
            fixture: fixture, leafKey: leafKey, signerKey: fixture.issuingKey,
            additionalExtensions: [
              DocumentSignerEligibilityTests.extendedKeyUsageExtension(oids: [oid], critical: true)
            ]
          )
        )
      }
      for rejectedLeaf in rejectedLeaves {
        let result = try Self.verifySignedPdf(
          fixture: fixture, intermediate: fixture.issuing, intermediateKey: fixture.issuingKey,
          leaf: rejectedLeaf, leafKey: leafKey
        )
        #expect(!result.document.isValid)
        #expect(!result.signature.chain.isAnchored)
      }
    }

    /// End-to-end PDF verification rejects a signer leaf issued under a TLS-restricted intermediate CA.
    @Test
    internal func endToEndVerificationRejectsRestrictedSubordinateCa() throws {
      let fixture = try DocumentTrustFixture()
      let leafKey = try CertificateRevocationListFixtures.makeKey(for: fixture.kind)
      let restrictedSubCaKey = try CertificateRevocationListFixtures.makeKey(for: fixture.kind)
      let restrictedSubCa = try CertificateRevocationListFixtures.certificate(
        description: .init(
          allowsCrlSigning: true,
          includesKeyUsage: true,
          malformedKeyUsage: false,
          commonName: CertificateRevocationListFixtures.issuerCommonName,
          isCertificateAuthority: true,
          issuerName: CertificateRevocationListFixtures.name(DocumentTrustFixture.rootName),
          serial: Self.subordinateCaSerial,
          additionalExtensions: [
            DocumentSignerEligibilityTests.extendedKeyUsageExtension(
              oids: [SignOids.serverAuthentication], critical: false
            )
          ]
        ),
        publicKey: restrictedSubCaKey,
        signer: fixture.rootKey,
        kind: fixture.kind
      )
      let leafUnderRestrictedSubCa = try Self.signerLeaf(
        fixture: fixture, leafKey: leafKey, signerKey: restrictedSubCaKey
      )
      let rejected = try Self.verifySignedPdf(
        fixture: fixture, intermediate: restrictedSubCa, intermediateKey: restrictedSubCaKey,
        leaf: leafUnderRestrictedSubCa, leafKey: leafKey
      )
      #expect(!rejected.document.isValid)
      #expect(!rejected.signature.chain.isAnchored)
    }
  }

#endif
