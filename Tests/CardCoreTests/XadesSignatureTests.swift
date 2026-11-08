// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import CardCore

/// The XAdES writer's one obligation: octets that are already in
/// canonical form, so a verifier's canonicalisation is the identity.
@Suite
internal struct XadesSignatureTests {
  /// A stand-in signer certificate.
  ///
  /// Its contents do not matter to these tests - only that its bytes
  /// are hashed into `CertDigest`.
  private static let certificate = Data(
    "not a real certificate, hashed all the same".utf8
  )

  /// A fixed instant so the expected `SigningTime` is a constant.
  private static let signedAt = Date(timeIntervalSince1970: 1_785_849_296)

  /// Empty validation material, for baseline-level documents.
  private static let noMaterial = PdfValidationStore.Material(
    certificates: [],
    ocspResponses: [],
    revocationLists: []
  )

  private static func sample() -> [AsicContainer.DataObject] {
    let object = AsicContainer.DataObject(
      name: "dossier.pdf",
      mimeType: "application/pdf",
      content: Data("a set of statements worth signing".utf8)
    )
    return [object]
  }

  private static func plan() throws -> XadesSignature.Plan {
    try #require(
      XadesSignature.plan(
        objects: Self.sample(),
        certificate: Self.certificate,
        profile: .ecdsaP384,
        signedAt: Self.signedAt
      )
    )
  }

  /// Decoded UTF-8, failing the test on undecodable bytes.
  private static func text(_ data: Data) throws -> String {
    try #require(String(bytes: data, encoding: .utf8))
  }

  /// A finished baseline document, as text.
  private static func baselineDocument() throws -> String {
    try Self.text(
      Self.plan().document(
        xmlSignature: Data("signature".utf8),
        timestampTokens: [],
        material: Self.noMaterial,
        archiveTimestampToken: nil
      )
    )
  }

  @Test
  internal func theSignedInfoIsAlreadyInCanonicalForm() throws {
    let signedInfo = try Self.text(Self.plan().signedInfo)
    // The three ways generated XML usually fails to be canonical.
    #expect(!signedInfo.contains("/>"), "no element may be self-closed")
    #expect(
      !signedInfo.contains("<?xml"),
      "a canonicalised subset carries no declaration"
    )
    #expect(
      signedInfo.hasPrefix("<ds:SignedInfo xmlns:ds="),
      "the subset root must declare the prefix it uses: \(signedInfo)"
    )
    #expect(
      signedInfo.hasSuffix("</ds:SignedInfo>"),
      "the octets end at the element, with no trailing newline"
    )
  }

  @Test
  internal func theSignedPropertiesDeclareBothPrefixesWhereUsed() throws {
    let document = try Self.baselineDocument()
    #expect(document.contains("<xades:SignedProperties xmlns:xades="))
    // `ds` is used only by the digest elements, so it is declared on
    // each of them and on no ancestor.
    #expect(document.contains("<ds:DigestMethod xmlns:ds="))
    #expect(document.contains("<ds:DigestValue xmlns:ds="))
    #expect(
      !document.contains("<xades:CertDigest xmlns:ds="),
      "no ancestor visibly uses ds, so none may declare it"
    )
    #expect(
      document.contains(
        "<xades:SigningTime>2026-08-04T13:14:56Z</xades:SigningTime>"
      )
    )
  }

  @Test
  internal func everyDataObjectGetsAReferenceAndAFormat() throws {
    let objects = [
      AsicContainer.DataObject(
        name: "a.pdf",
        mimeType: "application/pdf",
        content: Data("one".utf8)
      ),
      AsicContainer.DataObject(
        name: "b.txt",
        mimeType: "text/plain",
        content: Data("two".utf8)
      ),
    ]
    let plan = try #require(
      XadesSignature.plan(
        objects: objects,
        certificate: Self.certificate,
        profile: .ecdsaP384,
        signedAt: Self.signedAt
      )
    )
    let signedInfo = try Self.text(plan.signedInfo)
    let document = try Self.text(
      plan.document(
        xmlSignature: Data("signature".utf8),
        timestampTokens: [],
        material: Self.noMaterial,
        archiveTimestampToken: nil
      )
    )
    let expected = Data(SHA384.hash(data: Data("one".utf8)))
      .base64EncodedString()
    #expect(signedInfo.contains(#"<ds:Reference Id="SIG-1-REF-0" URI="a.pdf">"#))
    #expect(signedInfo.contains("<ds:DigestValue>\(expected)</ds:DigestValue>"))
    #expect(signedInfo.contains(#"<ds:Reference Id="SIG-1-REF-1" URI="b.txt">"#))
    // Each format entry points back at its reference by identifier.
    #expect(
      document.contains(
        ##"<xades:DataObjectFormat ObjectReference="#SIG-1-REF-0">"##
      )
    )
    #expect(document.contains("<xades:MimeType>text/plain</xades:MimeType>"))
  }

  @Test
  internal func theDocumentEmbedsTheSignedOctetsUnchanged() throws {
    let plan = try Self.plan()
    let signedInfo = try Self.text(plan.signedInfo)
    let document = try Self.text(
      plan.document(
        xmlSignature: Data("signature".utf8),
        timestampTokens: [],
        material: Self.noMaterial,
        archiveTimestampToken: nil
      )
    )
    #expect(
      document.contains(signedInfo),
      "what was signed must appear in the document byte for byte"
    )
  }

  @Test
  internal func emptyObjectsAreRefused() {
    #expect(
      XadesSignature.plan(
        objects: [],
        certificate: Self.certificate,
        profile: .ecdsaP384,
        signedAt: Self.signedAt
      ) == nil
    )
  }

  @Test
  internal func timestampsAndEvidenceLandInUnsignedProperties() throws {
    let token = Data("rfc3161 token".utf8)
    let material = PdfValidationStore.Material(
      certificates: [Data("issuer".utf8)],
      ocspResponses: [Data("ocsp".utf8)],
      revocationLists: [Data("crl".utf8)]
    )
    let document = try Self.text(
      Self.plan().document(
        xmlSignature: Data("signature".utf8),
        timestampTokens: [token],
        material: material,
        archiveTimestampToken: nil
      )
    )
    #expect(
      document.contains(
        #"<xades:SignatureTimeStamp xmlns:xades="http://uri.etsi.org/01903/v1.3.2#" Id="SIG-1-TS-0">"#
      )
    )
    #expect(
      document.contains(
        "<xades:EncapsulatedTimeStamp>\(token.base64EncodedString())"
      )
    )
    #expect(
      document.contains(
        #"<xades:CertificateValues xmlns:xades="http://uri.etsi.org/01903/v1.3.2#">"#
      )
    )
    // Schema order inside RevocationValues: CRLs before OCSP responses.
    let crlValues = try #require(document.range(of: "<xades:CRLValues>"))
    let ocspValues = try #require(document.range(of: "<xades:OCSPValues>"))
    #expect(crlValues.lowerBound < ocspValues.lowerBound)
  }

  @Test
  internal func baselineDocumentsCarryNoUnsignedProperties() throws {
    let document = try Self.baselineDocument()
    #expect(!document.contains("<xades:UnsignedProperties>"))
  }

  @Test
  internal func theTimestampCoversTheCanonicalSignatureValueElement() {
    let signature = Data("signature".utf8)
    let element = XadesSignature.signatureValueElement(signature)
    #expect(
      element
        == #"<ds:SignatureValue xmlns:ds="http://www.w3.org/2000/09/xmldsig#" "#
        + #"Id="SIG-1-SIGVAL">"#
        + signature.base64EncodedString()
        + "</ds:SignatureValue>"
    )
    #expect(
      XadesSignature.timestampDigest(signature)
        == Data(SHA384.hash(data: Data(element.utf8)))
    )
  }

  @Test
  internal func theSignatureMethodFollowsTheKeyUnderSha384() {
    #expect(
      XadesSignature.signatureMethod(.ecdsaP384)
        == "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384"
    )
    #expect(
      XadesSignature.signatureMethod(.rsa2048)
        == "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384"
    )
  }

  @Test
  internal func escapingFollowsTheCanonicalisationRulesNotTheXmlOnes() {
    // `>` and `'` stay raw in an attribute value; a canonicaliser
    // writes them raw, so escaping them would change the digest.
    #expect(XadesSignature.escapeAttribute("a>b'c") == "a>b'c")
    #expect(
      XadesSignature.escapeAttribute("a&b\"c<d") == "a&amp;b&quot;c&lt;d"
    )
    #expect(XadesSignature.escapeAttribute("a\nb") == "a&#xA;b")
    // `>` is escaped in text, where the rule is the other way round.
    #expect(XadesSignature.escapeText("a>b'c") == "a&gt;b'c")
    #expect(XadesSignature.escapeText("a&b<c") == "a&amp;b&lt;c")
  }

  @Test
  internal func referenceUrisArePercentEncodedForNonAsciiNames() throws {
    let nonAsciiObject = AsicContainer.DataObject(
      name: "Nimetön.pdf",
      mimeType: "application/pdf",
      content: Data("document".utf8)
    )
    let plan = try #require(
      XadesSignature.plan(
        objects: [nonAsciiObject],
        certificate: Self.certificate,
        profile: .ecdsaP384,
        signedAt: Self.signedAt
      )
    )
    let signedInfo = try #require(String(bytes: plan.signedInfo, encoding: .utf8))
    #expect(signedInfo.contains(#"URI="Nimet%C3%B6n.pdf""#))
    #expect(!signedInfo.contains(#"URI="Nimetön.pdf""#))
  }
}
