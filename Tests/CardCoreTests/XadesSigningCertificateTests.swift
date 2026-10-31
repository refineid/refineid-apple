// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import CardCore

/// The XAdES signing-certificate binding (EN 319 132-1 clause 5.2.2),
/// on signatures whose references and signature value are intact.
@Suite
internal struct XadesSigningCertificateTests {
  /// One signed fixture: the signatures file and its signer.
  private struct Signed {
    let document: String
    let identity: QualifiedDocumentCmsTests.Identity
  }

  private static let profile = CardKeyProfile.ecdsaP384
  private static let versionTwoOpen = "<xades:SigningCertificateV2>"
  private static let versionTwoClose = "</xades:SigningCertificateV2>\n"
  private static let versionOneOpen = "<xades:SigningCertificate>"
  private static let versionOneClose = "</xades:SigningCertificate>\n"
  private static let certDigestClose = "</xades:CertDigest>\n"
  private static let digestValueOpen = "<ds:DigestValue xmlns:ds="
  private static let digestValueClose = "</ds:DigestValue>"
  private static let keyInfoCertificateOpen = "<ds:X509Certificate>"
  private static let unknownDigestMethod = "urn:example:unknown-digest"
  private static let issuerNameText = "CN=RefineID Document CMS Test"

  /// A signature over the sample objects whose SignedProperties text
  /// `edit` changes before it is digested and the SignedInfo signed.
  private static func signed(
    carrying certificates: [Data] = [],
    editingProperties edit: (String, QualifiedDocumentCmsTests.Identity) throws -> String
  ) throws -> Signed {
    let objects = AsicVerificationTests.sampleObjects()
    let identity = try QualifiedDocumentCmsTests.identity(Self.profile)
    let properties = try edit(
      XadesSignature.signedProperties(
        objects: objects,
        certificate: identity.certificate,
        signedAt: AsicVerificationTests.signedAt
      ),
      identity
    )
    let info = XadesSignature.signedInfo(
      objects: objects,
      profile: Self.profile,
      propertiesDigest: Data(SHA384.hash(data: Data(properties.utf8)))
    )
    let plan = XadesSignature.Plan(
      signedInfoXml: info,
      signedPropertiesXml: properties,
      certificateDer: identity.certificate
    )
    let signature = try AsicVerificationTests.xmlSignature(
      over: plan.signedInfo, identity: identity, profile: Self.profile)
    let document = plan.document(
      xmlSignature: signature,
      timestampTokens: [],
      material: PdfValidationStore.Material(
        certificates: certificates, ocspResponses: [], revocationLists: [])
    )
    return Signed(
      document: try #require(String(data: document, encoding: .utf8)),
      identity: identity
    )
  }

  /// The rows of one signatures file in the sample container.
  private static func rows(_ document: String) throws -> DocumentVerification.DocumentReport {
    try AsicVerification.verify(container: AsicVerificationTests.container(document: document))
  }

  /// The range of `open` through `close` in `text`.
  private static func range(
    of open: String, through close: String, in text: String
  ) throws -> Range<String.Index> {
    let start = try #require(text.range(of: open))
    let end = try #require(text.range(of: close, range: start.upperBound..<text.endIndex))
    return start.lowerBound..<end.upperBound
  }

  /// `properties` with its CertDigest value replaced by `digest`.
  private static func replacingCertDigest(_ properties: String, with digest: Data) throws
    -> String
  {
    let property = try #require(properties.range(of: Self.versionTwoOpen))
    let open = try #require(
      properties.range(of: Self.digestValueOpen, range: property.upperBound..<properties.endIndex))
    let valueStart = try #require(
      properties.range(of: ">", range: open.upperBound..<properties.endIndex))
    let valueEnd = try #require(
      properties.range(
        of: Self.digestValueClose, range: valueStart.upperBound..<properties.endIndex)
    )
    var edited = properties
    edited.replaceSubrange(
      valueStart.upperBound..<valueEnd.lowerBound, with: digest.base64EncodedString())
    return edited
  }

  /// `properties` with `element` placed after the CertDigest.
  private static func addingToCert(_ element: String, in properties: String) throws -> String {
    var edited = properties
    let close = try #require(edited.range(of: Self.certDigestClose))
    edited.insert(contentsOf: element + "\n", at: close.upperBound)
    return edited
  }

  /// The RFC 5035 IssuerSerial naming `issuer` and `serial`.
  private static func issuerSerial(issuer: Data, serial: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.sequence([DerEncoder.tlv(DerValues.tagContext4Constructed, issuer)]),
      DerEncoder.tlv(DerValues.tagInteger, serial),
    ])
  }

  @Test
  internal func boundSignatureIsValid() throws {
    let signed = try Self.signed { properties, _ in properties }
    let report = try #require(Self.rows(signed.document).judged.first)

    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  @Test
  internal func signatureWithoutSigningCertificateIsNotValid() throws {
    let signed = try Self.signed { properties, _ in
      var edited = properties
      edited.removeSubrange(
        try Self.range(of: Self.versionTwoOpen, through: Self.versionTwoClose, in: properties))
      return edited
    }
    let report = try #require(Self.rows(signed.document).judged.first)

    #expect(report.documentIntact)
    #expect(!report.signatureValid)
  }

  @Test
  internal func certDigestNamingAnotherCarriedCertificateIsNotValid() throws {
    let other = try QualifiedDocumentCmsTests.identity(Self.profile)
    let signed = try Self.signed(carrying: [other.certificate]) { properties, _ in
      try Self.replacingCertDigest(properties, with: Data(SHA384.hash(data: other.certificate)))
    }
    let report = try #require(Self.rows(signed.document).judged.first)

    #expect(report.documentIntact)
    #expect(!report.signatureValid)
  }

  @Test
  internal func certDigestNamingNoCarriedCertificateIsUnsupported() throws {
    let other = try QualifiedDocumentCmsTests.identity(Self.profile)
    let signed = try Self.signed { properties, _ in
      try Self.replacingCertDigest(properties, with: Data(SHA384.hash(data: other.certificate)))
    }
    let report = try Self.rows(signed.document)

    #expect(report.signatures.count == 1)
    #expect(report.judged.isEmpty)
  }

  @Test
  internal func unknownCertDigestMethodIsUnsupported() throws {
    let signed = try Self.signed { properties, _ in
      let property = try #require(properties.range(of: Self.versionTwoOpen))
      var edited = properties
      let method = try #require(
        edited.range(
          of: XadesSignature.digestMethodSha384, range: property.upperBound..<edited.endIndex))
      edited.replaceSubrange(method, with: Self.unknownDigestMethod)
      return edited
    }

    #expect(try Self.rows(signed.document).judged.isEmpty)
  }

  @Test
  internal func matchingIssuerSerialV2IsAccepted() throws {
    let signed = try Self.signed { properties, identity in
      let facts = try #require(CertificateFacts(der: identity.certificate))
      let der = Self.issuerSerial(issuer: facts.issuerName, serial: facts.serialNumber)
      return try Self.addingToCert(
        "<xades:IssuerSerialV2>\(der.base64EncodedString())</xades:IssuerSerialV2>",
        in: properties)
    }
    let report = try #require(Self.rows(signed.document).judged.first)

    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  @Test
  internal func issuerSerialV2WithAnotherSerialIsRefused() throws {
    let signed = try Self.signed { properties, identity in
      let facts = try #require(CertificateFacts(der: identity.certificate))
      let der = Self.issuerSerial(
        issuer: facts.issuerName, serial: facts.serialNumber + facts.serialNumber)
      return try Self.addingToCert(
        "<xades:IssuerSerialV2>\(der.base64EncodedString())</xades:IssuerSerialV2>",
        in: properties)
    }

    #expect(try Self.rows(signed.document).judged.isEmpty)
  }

  @Test
  internal func matchingIssuerSerialTextIsAccepted() throws {
    let signed = try Self.signed { properties, identity in
      let facts = try #require(CertificateFacts(der: identity.certificate))
      let serial = AsicVerification.decimal(facts.serialNumber)
      return try Self.addingToCert(
        "<xades:IssuerSerial><ds:X509IssuerName>\(Self.issuerNameText)</ds:X509IssuerName>"
          + "<ds:X509SerialNumber>\(serial)</ds:X509SerialNumber></xades:IssuerSerial>",
        in: properties)
    }
    let report = try #require(Self.rows(signed.document).judged.first)

    #expect(report.signatureValid)
  }

  @Test
  internal func issuerSerialTextWithAnotherSerialIsRefused() throws {
    let signed = try Self.signed { properties, identity in
      let facts = try #require(CertificateFacts(der: identity.certificate))
      let serial = AsicVerification.decimal(facts.serialNumber + facts.serialNumber)
      return try Self.addingToCert(
        "<xades:IssuerSerial><ds:X509IssuerName>\(Self.issuerNameText)</ds:X509IssuerName>"
          + "<ds:X509SerialNumber>\(serial)</ds:X509SerialNumber></xades:IssuerSerial>",
        in: properties)
    }

    #expect(try Self.rows(signed.document).judged.isEmpty)
  }

  @Test
  internal func bothSigningCertificateVersionsAreNotValid() throws {
    let signed = try Self.signed { properties, _ in
      let block = String(
        properties[
          try Self.range(of: Self.versionTwoOpen, through: Self.versionTwoClose, in: properties)])
      let versionOne =
        block
        .replacingOccurrences(of: Self.versionTwoOpen, with: Self.versionOneOpen)
        .replacingOccurrences(of: Self.versionTwoClose, with: Self.versionOneClose)
      return properties.replacingOccurrences(of: block, with: block + versionOne)
    }
    let report = try #require(Self.rows(signed.document).judged.first)

    #expect(report.documentIntact)
    #expect(!report.signatureValid)
  }

  /// `ds:KeyInfo` is not signed; a certificate listed before the signer
  /// does not move the binding off the signer.
  @Test
  internal func keyInfoCertificateBeforeTheSignerStillBindsTheSigner() throws {
    let other = try QualifiedDocumentCmsTests.identity(Self.profile)
    let signed = try Self.signed { properties, _ in properties }
    var document = signed.document
    let keyInfo = try #require(document.range(of: Self.keyInfoCertificateOpen))
    document.insert(
      contentsOf: Self.keyInfoCertificateOpen + other.certificate.base64EncodedString()
        + "</ds:X509Certificate>\n",
      at: keyInfo.lowerBound)
    let report = try #require(Self.rows(document).judged.first)

    #expect(report.signerCertificate == signed.identity.certificate)
    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  /// The decimal spelling of a magnitude.
  @Test
  internal func decimalSpellsTheMagnitude() {
    #expect(AsicVerification.decimal(Data()) == "0")
    #expect(AsicVerification.decimal(Data([UInt8(ascii: "*")])) == "42")
    #expect(AsicVerification.decimal(Data([UInt8(ascii: "\n"), UInt8(ascii: "\0")])) == "2560")
  }
}
