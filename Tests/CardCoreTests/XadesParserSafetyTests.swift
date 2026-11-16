// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Element bounds, nesting, and refused documents in the XAdES parser.
@Suite
internal struct XadesParserSafetyTests {
  private static let xmlDeclarationClose = "?>"
  private static let referenceOpen = "<ds:Reference "
  private static let secondSignatureId = "SIG-2"
  private static let internalEntity =
    "\n<!DOCTYPE asic:XAdESSignatures [<!ENTITY stand \"in\">]>"
  private static let unreferencedFile = AsicContainer.DataObject(
    name: "unreferenced.txt",
    mimeType: "text/plain",
    content: Data("A file no reference covers.".utf8)
  )

  @Test
  internal func selfClosingTagsWithWhitespaceOrAttributesParse() throws {
    let document = #"<root><empty /><marked kind="x"/><plain/></root>"#
    let parsed = try XmlDocument(Data(document.utf8))

    #expect(parsed.elementCount == 4)
    #expect(parsed.root.children.map(\.localName) == ["empty", "marked", "plain"])
    #expect(parsed.root.children[1].attribute("kind") == "x")
  }

  @Test
  internal func elementCountAboveTheCeilingIsRefused() {
    let inner = String(repeating: "<e/>", count: XmlParser.maximumNodes)
    let parser = XadesXmlParser()

    #expect(parser.parse(data: Data("<root>\(inner)</root>".utf8)).isEmpty)
    #expect(!parser.parsedWholeDocument)
  }

  @Test
  internal func documentTypeWithAnInternalEntityIsRefused() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    var document = signed.document
    let declaration = try #require(document.range(of: Self.xmlDeclarationClose))
    document.insert(contentsOf: Self.internalEntity, at: declaration.upperBound)

    let parser = XadesXmlParser()
    #expect(parser.parse(data: Data(document.utf8)).isEmpty)
    #expect(!parser.parsedWholeDocument)
    let report = try AsicVerification.verify(
      container: AsicVerificationTests.container(document: document), anchors: .empty)
    #expect(report.signatures.count == 1)
    #expect(report.judged.isEmpty)
  }

  /// A `ds:Signature` nested inside the outer signature's
  /// `ds:Reference` leaves the outer's references as they were, while marking the outer invalid.
  @Test
  internal func signatureNestedInAReferenceLeavesTheOuterReferences() throws {
    let outer = try AsicVerificationTests.signedDocument(profile: .ecdsaP384).document
    let inner = try XadesXmlParserTests.signatureElement(
      of: XadesXmlParserTests.signedDocument(
        profile: .ecdsaP384, signatureId: Self.secondSignatureId
      ).document)
    let reference = try #require(outer.range(of: Self.referenceOpen))
    let tagEnd = try #require(outer.range(of: ">", range: reference.upperBound..<outer.endIndex))
    var nested = outer
    nested.insert(contentsOf: "\n" + inner, at: tagEnd.upperBound)

    let plain = try #require(XadesXmlParserTests.parse(outer).first)
    let parsed = XadesXmlParserTests.parse(nested)
    try #require(parsed.count == 2)
    let expected = XadesXmlParserTests.references(of: plain)
    let actual = XadesXmlParserTests.references(of: parsed[0])
    try #require(!expected.isEmpty)
    #expect(actual.map(\.uri) == expected.map(\.uri))
    #expect(actual.map(\.digestValue) == expected.map(\.digestValue))
    #expect(actual.map(\.transforms) == expected.map(\.transforms))
    #expect(!parsed[0].isCounterSignature)
    #expect(parsed[0].hasStructuralError)
    #expect(parsed[1].isCounterSignature)
  }

  /// A data file outside META-INF that no reference covers makes the
  /// signature not intact.
  @Test
  internal func unreferencedDataFileIsNotIntact() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let container = try #require(
      AsicContainer.container(
        objects: AsicVerificationTests.sampleObjects() + [Self.unreferencedFile],
        signatureXml: Data(signed.document.utf8)))
    let report = try AsicVerificationTests.report(container)

    #expect(report.signatureValid)
    #expect(!report.documentIntact)
  }
}
