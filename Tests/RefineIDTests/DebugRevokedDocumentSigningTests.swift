// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineID

  /// Direct checks for the development-only revoked-signer escape hatch.
  @Suite
  internal struct DebugRevokedDocumentSigningTests {
    /// The saved file has exactly the staged CMS and no later evidence.
    private static func expectOnlyBtRevision(
      _ document: Data,
      cms: Data
    ) throws {
      let contents = try #require(
        DebugRevokedDocumentSigningFixture.embeddedContents(in: document)
      )
      #expect(contents.prefix(cms.count) == cms)
      #expect(contents.dropFirst(cms.count).allSatisfy { byte in byte == 0 })

      let text = try #require(String(data: document, encoding: .isoLatin1))
      #expect(text.contains("/SubFilter /ETSI.CAdES.detached"))
      #expect(text.contains(DebugRevokedDocumentSigning.reason))
      #expect(!text.contains("/DSS"))
      #expect(!text.contains("/Type /DocTimeStamp"))
      #expect(!text.contains("/SubFilter /ETSI.RFC3161"))
    }

    @Test
    internal func launchArgumentMustBeExplicitAndExact() {
      #expect(
        DebugRevokedDocumentSigning.isEnabled(
          arguments: ["RefineID", DebugRevokedDocumentSigning.launchArgument]
        )
      )
      #expect(
        !DebugRevokedDocumentSigning.isEnabled(
          arguments: ["RefineID", "--allow-revoked"]
        )
      )
      #expect(
        !DebugRevokedDocumentSigning.isEnabled(
          arguments: [
            "RefineID",
            DebugRevokedDocumentSigning.launchArgument,
            DebugLaunchMode.signDocument.rawValue,
          ]
        )
      )
    }

    @Test
    internal func authenticatedRevocationKeepsAValidBtRevisionOnly() throws {
      let fixture = try DebugRevokedDocumentSigningFixture.make()
      let parsedToken = try RfcTimestamp.token(
        fromResponse: fixture.timestampResponse,
        digest: fixture.timestampImprint,
        nonceBytes: fixture.timestampNonce
      )
      let verifiedToken = try TimestampTokenVerifier.verify(
        parsedToken,
        trustedCertificates: [fixture.timestampCertificate]
      )
      let product = try #require(
        DebugRevokedDocumentSigning.product(
          timestamped: fixture.timestamped,
          after: ValidationMaterialCollector.Failure.revoked(.documentSigner),
          enabled: true
        )
      )

      #expect(parsedToken == fixture.timestampToken)
      #expect(verifiedToken.token == fixture.timestampToken)
      #expect(
        try DebugRevokedDocumentSigningFixture.cardSignatureIsValid(fixture)
      )
      #expect(fixture.cms.contains(fixture.timestampToken))
      #expect(
        fixture.cms.contains(
          DerEncoder.objectIdentifier(SignOids.signatureTimestampToken)
        )
      )
      #expect(CmsCertificates.inside(fixture.cms) == [fixture.cardCertificate])
      #expect(
        CmsCertificates.inside(fixture.timestampToken)
          .contains(fixture.timestampCertificate)
      )
      #expect(product.bytes == fixture.timestamped.bytes)
      #expect(product.completion == .revokedSignerTest)
      try Self.expectOnlyBtRevision(product.bytes, cms: fixture.cms)
    }

    @Test
    internal func timestampedStageRequiresAnAuthenticatedToken() throws {
      let fixture = try DebugRevokedDocumentSigningFixture.make()

      #expect(
        throws: DocumentSigner.TimestampedSignatureFailure.timestampMissing
      ) {
        _ = try DocumentSigner.TimestampedSignature.verified(
          DocumentSigner.TimestampedSignatureInput(
            placeholder: fixture.placeholder,
            signedAttributes: fixture.signedAttributes,
            signatureValue: fixture.cardSignature,
            signerProfile: .rsa2048,
            signerCertificate: fixture.cardCertificate
          ),
          timestampTokens: []
        )
      }
    }

    @Test
    internal func everyOtherEvidenceFailureStillRefuses() throws {
      let timestamped = try DebugRevokedDocumentSigningFixture.make().timestamped

      #expect(
        DebugRevokedDocumentSigning.product(
          timestamped: timestamped,
          after: ValidationMaterialCollector.Failure.revoked(.documentSigner),
          enabled: false
        ) == nil
      )
      #expect(
        DebugRevokedDocumentSigning.product(
          timestamped: timestamped,
          after: ValidationMaterialCollector.Failure.revoked(
            .timestampAuthority
          ),
          enabled: true
        ) == nil
      )
      #expect(
        DebugRevokedDocumentSigning.product(
          timestamped: timestamped,
          after: ValidationMaterialCollector.Failure.revocationUnavailable,
          enabled: true
        ) == nil
      )
      #expect(
        DebugRevokedDocumentSigning.product(
          timestamped: timestamped,
          after: ValidationMaterialCollector.Failure.issuerUnavailable,
          enabled: true
        ) == nil
      )
    }

    @Test
    internal func outputWarningNamesTheDeliberatelyReducedLevel() {
      #expect(DebugRevokedDocumentSigning.warning.contains("PAdES-B-T"))
      #expect(DebugRevokedDocumentSigning.warning.contains("no LT/LTA"))
      #expect(
        DebugRevokedDocumentSigning.warning.contains("document timestamp")
      )
    }
  }

#endif
