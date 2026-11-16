// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

#if os(macOS)
  /// Hardening tests ensuring validation material appended after `xadesv141:ArchiveTimeStamp` cannot credit `B-LTA`.
  @Suite
  internal struct AsicArchiveHardeningTests {
    private static let asicSignerBits = 2_048
    private static let unsignedSignaturePropertiesClose = "</xades:UnsignedSignatureProperties>"

    @Test
    internal func revocationValuesPlacedAfterArchiveTimestampDoNotCreditLongTermArchival() throws {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.asicSignerBits)
      let identity = fixture.signer
      let objects = AsicVerificationTests.sampleObjects()
      let plan = try #require(
        XadesSignature.plan(
          objects: objects,
          certificate: identity.certificate,
          profile: identity.profile,
          signedAt: AsicVerificationTests.signedAt
        ))
      let signature = try AsicVerificationTests.xmlSignature(
        over: plan.signedInfo, identity: identity, profile: identity.profile)
      let sigToken = try fixture.authority.token(
        imprint: XadesSignature.timestampDigest(signature),
        generalizedTime: SignatureLevelTests.signatureStampTime
      )
      let preArchiveMaterial = PdfValidationStore.Material(
        certificates: [fixture.issuing, fixture.authority.certificate],
        ocspResponses: [],
        revocationLists: []
      )
      let archiveToken = try fixture.authority.token(
        imprint: plan.archiveTimestampDigest(
          xmlSignature: signature, timestampTokens: [sigToken], material: preArchiveMaterial),
        generalizedTime: SignatureLevelTests.archiveStampTime
      )
      let rawDoc = plan.document(
        xmlSignature: signature,
        timestampTokens: [sigToken],
        material: preArchiveMaterial,
        archiveTimestampToken: archiveToken
      )
      var xml = try #require(String(data: rawDoc, encoding: .utf8))
      let crls = try SignatureLevelTests.pathRevocationLists(fixture)
      let encodedCrls = crls.map { crl in
        "<xades:EncapsulatedCRLValue>\(crl.base64EncodedString())</xades:EncapsulatedCRLValue>"
      }
      let trailingRevocation =
        "<xades:RevocationValues><xades:CRLValues>"
        + encodedCrls.joined()
        + "</xades:CRLValues></xades:RevocationValues>\n"
      let closeRange = try #require(xml.range(of: Self.unsignedSignaturePropertiesClose))
      xml.insert(contentsOf: trailingRevocation, at: closeRange.lowerBound)

      let container = try #require(
        AsicContainer.container(objects: objects, signatureXml: Data(xml.utf8)))
      let report = try SignatureLevelTests.anchoredReport(container, fixture)

      #expect(report.isValid)
      #expect(report.level == .longTerm)
      #expect(report.archiveValidUntil == nil)
      #expect(report.archiveTimestamps.isEmpty)
    }

    @Test
    internal func intermediateCertificatePlacedAfterArchiveTimestampDoesNotCreditLongTermArchival()
      throws
    {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.asicSignerBits)
      let identity = fixture.signer
      let objects = AsicVerificationTests.sampleObjects()
      let plan = try #require(
        XadesSignature.plan(
          objects: objects,
          certificate: identity.certificate,
          profile: identity.profile,
          signedAt: AsicVerificationTests.signedAt
        ))
      let signature = try AsicVerificationTests.xmlSignature(
        over: plan.signedInfo, identity: identity, profile: identity.profile)
      let sigToken = try fixture.authority.token(
        imprint: XadesSignature.timestampDigest(signature),
        generalizedTime: SignatureLevelTests.signatureStampTime
      )
      let crls = try SignatureLevelTests.pathRevocationLists(fixture)
      let preArchiveMaterial = PdfValidationStore.Material(
        certificates: [fixture.authority.certificate],
        ocspResponses: [],
        revocationLists: crls
      )
      let archiveToken = try fixture.authority.token(
        imprint: plan.archiveTimestampDigest(
          xmlSignature: signature, timestampTokens: [sigToken], material: preArchiveMaterial),
        generalizedTime: SignatureLevelTests.archiveStampTime
      )
      let rawDoc = plan.document(
        xmlSignature: signature,
        timestampTokens: [sigToken],
        material: preArchiveMaterial,
        archiveTimestampToken: archiveToken
      )
      var xml = try #require(String(data: rawDoc, encoding: .utf8))
      let trailingCert =
        "<xades:CertificateValues><xades:EncapsulatedX509Certificate>"
        + fixture.issuing.base64EncodedString()
        + "</xades:EncapsulatedX509Certificate></xades:CertificateValues>\n"
      let closeRange = try #require(xml.range(of: Self.unsignedSignaturePropertiesClose))
      xml.insert(contentsOf: trailingCert, at: closeRange.lowerBound)

      let container = try #require(
        AsicContainer.container(objects: objects, signatureXml: Data(xml.utf8)))
      let report = try SignatureLevelTests.anchoredReport(container, fixture)

      #expect(report.isValid)
      #expect(report.level == .longTerm)
      #expect(report.archiveValidUntil == nil)
      #expect(report.archiveTimestamps.isEmpty)
    }
  }
#endif
