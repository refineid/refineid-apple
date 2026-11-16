// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

/// Hardening tests for XML Signature Wrapping (XSW), canonicalisation, and algorithm rules.
@Suite
internal struct XadesWrappingHardeningTests {
  private static let signedInfoOpen = "<ds:SignedInfo"
  private static let signedInfoClose = "</ds:SignedInfo>"
  private static let signedPropertiesOpen = "<xades:SignedProperties"
  private static let qualifyingPropertiesClose = "</xades:QualifyingProperties>"
  private static let uppercaseSignatureFileName = "META-INF/SIGNATURES0.XML"
  private static let p384CoordinateOctets = 48
  private static let p384RawByteCount = 96
  private static let coordinatePaddingOctets = 16
  private static let oversizedSignatureByteCount = 512
  private static let nonZeroSignatureByte: UInt8 = 1
  private static let injectedFile = AsicContainer.DataObject(
    name: "contract.pdf",
    mimeType: "application/pdf",
    content: Data("Unsigned attacker contract payload.".utf8)
  )

  private static var dummySignedInfo: String {
    let digest = Data(SHA384.hash(data: Self.injectedFile.content)).base64EncodedString()
    return #"<ds:SignedInfo xmlns:ds="\#(XadesSignature.namespaceDsig)">"# + "\n"
      + #"<ds:CanonicalizationMethod Algorithm="\#(XadesSignature.canonicalizationExclusive)">"#
      + "</ds:CanonicalizationMethod>\n"
      + #"<ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384">"#
      + "</ds:SignatureMethod>\n"
      + #"<ds:Reference Id="FORGED-REF" URI="\#(Self.injectedFile.name)">"# + "\n"
      + #"<ds:DigestMethod Algorithm="\#(XadesSignature.digestMethodSha384)"></ds:DigestMethod>"#
      + "\n<ds:DigestValue>\(digest)</ds:DigestValue>\n"
      + "</ds:Reference>\n</ds:SignedInfo>\n"
  }

  private static var foreignNamespaceSignedInfo: String {
    let digest = Data(SHA384.hash(data: Self.injectedFile.content)).base64EncodedString()
    return #"<u:SignedInfo xmlns:u="urn:wrap">"# + "\n"
      + #"<u:CanonicalizationMethod Algorithm="\#(XadesSignature.canonicalizationExclusive)"/>"#
      + #"<u:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384"/>"#
      + #"<u:Reference URI="\#(Self.injectedFile.name)">"#
      + #"<u:DigestMethod Algorithm="\#(XadesSignature.digestMethodSha384)"/>"#
      + "<u:DigestValue>\(digest)</u:DigestValue>"
      + "</u:Reference></u:SignedInfo>\n"
  }

  private static func containerWithInjectedFile(signatureXml: String) throws -> Data {
    try #require(
      AsicContainer.container(
        objects: AsicVerificationTests.sampleObjects() + [Self.injectedFile],
        signatureXml: Data(signatureXml.utf8)
      ))
  }

  @Test
  internal func prependedOrAppendedDsigSignedInfoFailsVerification() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let prepended = try XadesXmlParserTests.inserting(
      Self.dummySignedInfo, before: Self.signedInfoOpen, in: signed.document)
    let closeRange = try #require(signed.document.range(of: Self.signedInfoClose))
    var appended = signed.document
    appended.insert(contentsOf: "\n" + Self.dummySignedInfo, at: closeRange.upperBound)

    for candidate in [prepended, appended] {
      let report = try AsicVerification.verify(
        container: Self.containerWithInjectedFile(signatureXml: candidate), anchors: .empty)
      #expect(!report.isValid)
      for judged in report.judged {
        #expect(!judged.signatureValid)
        #expect(!judged.documentIntact)
      }
    }
  }

  @Test
  internal func prependedOrAppendedForeignNamespaceSignedInfoFailsVerification() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let prepended = try XadesXmlParserTests.inserting(
      Self.foreignNamespaceSignedInfo, before: Self.signedInfoOpen, in: signed.document)
    let closeRange = try #require(signed.document.range(of: Self.signedInfoClose))
    var appended = signed.document
    appended.insert(contentsOf: "\n" + Self.foreignNamespaceSignedInfo, at: closeRange.upperBound)

    for candidate in [prepended, appended] {
      let report = try AsicVerification.verify(
        container: Self.containerWithInjectedFile(signatureXml: candidate), anchors: .empty)
      #expect(!report.isValid)
      for judged in report.judged {
        #expect(!judged.signatureValid)
        #expect(!judged.documentIntact)
      }
    }
  }

  @Test
  internal func secondSignedPropertiesInsideSignatureFailsVerification() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let other = try QualifiedDocumentCmsTests.identity(.ecdsaP384)
    let baseProps = XadesSignature.signedProperties(
      objects: AsicVerificationTests.sampleObjects(),
      certificate: other.certificate,
      signedAt: AsicVerificationTests.signedAt
    )
    let forgedProps = baseProps.replacingOccurrences(
      of: "Id=\"\(XadesSignature.signedPropertiesId)\"",
      with: "Id=\"FORGED-SIGNEDPROPS\""
    )
    let prepended = try XadesXmlParserTests.inserting(
      forgedProps + "\n", before: Self.signedPropertiesOpen, in: signed.document)
    let appended = try XadesXmlParserTests.inserting(
      forgedProps + "\n", before: Self.qualifyingPropertiesClose, in: signed.document)
    let secondObject = try XadesXmlParserTests.inserting(
      #"<ds:Object><xades:QualifyingProperties xmlns:xades="\#(XadesSignature.namespaceXades)" "#
        + #"Target="\#(AsicVerification.sameDocumentUriPrefix + XadesSignature.signatureId)">"#
        + forgedProps + "</xades:QualifyingProperties></ds:Object>\n",
      before: "</ds:Signature>",
      in: signed.document
    )

    for candidate in [prepended, appended, secondObject] {
      let report = try AsicVerification.verify(
        container: AsicVerificationTests.container(document: candidate), anchors: .empty)
      #expect(!report.isValid)
      for judged in report.judged {
        #expect(!judged.signatureValid)
        #expect(!judged.documentIntact)
      }
    }
  }

  @Test
  internal func rawSignedInfoSignatureOverCommentFailsWhenCanonicalizerOmitsComments() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let start = try #require(signed.document.range(of: Self.signedInfoOpen))
    let end = try #require(
      signed.document.range(
        of: Self.signedInfoClose, range: start.lowerBound..<signed.document.endIndex))
    var commentedInfo = String(signed.document[start.lowerBound..<end.upperBound])
    let tagClose = try #require(commentedInfo.firstIndex(of: ">"))
    commentedInfo.insert(
      contentsOf: "<!--unverified comment-->", at: commentedInfo.index(after: tagClose))

    let rawSig = try AsicVerificationTests.xmlSignature(
      over: Data(commentedInfo.utf8), identity: signed.identity, profile: .ecdsaP384)
    var tampered = signed.document
    tampered.replaceSubrange(start.lowerBound..<end.upperBound, with: commentedInfo)
    tampered = tampered.replacingOccurrences(
      of: XadesSignature.signatureValueElement(signed.xmlSignature),
      with: XadesSignature.signatureValueElement(rawSig)
    )

    let report = try AsicVerificationTests.report(
      AsicVerificationTests.container(document: tampered))
    #expect(!report.signatureValid)
  }

  @Test
  internal func derEncodedEcdsaSignatureValueIsRejected() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let derSignature = try #require(EcdsaSignature.derFromRawConcatenation(signed.xmlSignature))
    let replaced = signed.document.replacingOccurrences(
      of: XadesSignature.signatureValueElement(signed.xmlSignature),
      with: XadesSignature.signatureValueElement(derSignature)
    )

    let report = try AsicVerificationTests.report(
      AsicVerificationTests.container(document: replaced))
    #expect(!report.signatureValid)
  }

  @Test
  internal func uppercaseXadesSignatureEntryNameIsJudged() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    var writer = AsicContainer.ZipWriter()
    writer.add(name: AsicContainer.mimetypeEntryName, content: Data(AsicContainer.mimeType.utf8))
    for object in AsicVerificationTests.sampleObjects() {
      writer.add(name: object.name, content: object.content)
    }
    writer.add(name: Self.uppercaseSignatureFileName, content: Data(signed.document.utf8))
    let archive = try #require(writer.finish())

    let report = try AsicVerificationTests.report(archive)
    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  @Test
  internal func qualifyingPropertiesWithoutMatchingTargetFailsVerification() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let targetAttr =
      "Target=\"\(AsicVerification.sameDocumentUriPrefix + XadesSignature.signatureId)\""
    let withoutTarget = signed.document.replacingOccurrences(of: targetAttr, with: "")
    let wrongTarget = signed.document.replacingOccurrences(
      of: targetAttr, with: "Target=\"#OTHER-SIG\"")
    try #require(withoutTarget != signed.document)
    try #require(wrongTarget != signed.document)

    for candidate in [withoutTarget, wrongTarget] {
      let report = try AsicVerification.verify(
        container: AsicVerificationTests.container(document: candidate), anchors: .empty)
      #expect(!report.isValid)
      for judged in report.judged {
        #expect(!judged.signatureValid)
        #expect(!judged.documentIntact)
      }
    }
  }

  @Test
  internal func oversizedZeroPaddedAndZeroEcdsaSignaturesAreRejected() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let rHalf = signed.xmlSignature.prefix(Self.p384CoordinateOctets)
    let sHalf = signed.xmlSignature.suffix(Self.p384CoordinateOctets)
    let pad = Data(repeating: .zero, count: Self.coordinatePaddingOctets)
    let zeroPadded = pad + rHalf + pad + sHalf
    let oversized = Data(
      repeating: Self.nonZeroSignatureByte, count: Self.oversizedSignatureByteCount)
    let allZero = Data(repeating: .zero, count: Self.p384RawByteCount)

    #expect(EcdsaSignature.derFromRawConcatenation(oversized) == nil)
    #expect(EcdsaSignature.derFromRawConcatenation(allZero) == nil)

    for candidateSig in [zeroPadded, oversized, allZero] {
      let replaced = signed.document.replacingOccurrences(
        of: XadesSignature.signatureValueElement(signed.xmlSignature),
        with: XadesSignature.signatureValueElement(candidateSig)
      )
      let report = try AsicVerificationTests.report(
        AsicVerificationTests.container(document: replaced))
      #expect(!report.signatureValid)
    }
  }
}
