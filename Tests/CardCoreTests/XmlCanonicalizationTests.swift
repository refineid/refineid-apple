// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The XML reader and the three canonicalisations it renders.
@Suite
internal struct XmlCanonicalizationTests {
  /// A document whose root is prefixed and whose default namespace is
  /// declared beside it.
  private static let prefixedRoot = #"<a:x xmlns:a="urn:a" xmlns="urn:d"><y a:k="v"/><a:z/></a:x>"#

  /// The children `prefixedRoot` has.
  private static let prefixedRootChildren = 2

  private static func parse(_ text: String) throws -> XmlDocument {
    try XmlDocument(Data(text.utf8))
  }

  private static func refusal(_ text: String) -> XmlReadError? {
    do {
      _ = try Self.parse(text)
      return nil
    } catch let error as XmlReadError {
      return error
    } catch {
      return nil
    }
  }

  /// `element` rendered under `method`, as text.
  private static func canonical(
    _ element: XmlElement,
    _ method: XmlCanonicalization,
    omitting: XmlElement? = nil
  ) throws -> String {
    let rendered = try #require(
      XmlCanonicalizer.canonicalize(element, method: method, omitting: omitting))
    return try #require(String(data: rendered, encoding: .utf8))
  }

  /// The first element of `document` named `localName`.
  private static func named(_ document: XmlDocument, _ localName: String) throws -> XmlElement {
    try #require(document.allElements().first { element in element.localName == localName })
  }

  @Test
  internal func prefixesResolveThroughDeclarationsInScope() throws {
    let document = try Self.parse(Self.prefixedRoot)
    let root = document.root
    #expect(root.matches("urn:a", "x"))
    let children = root.children
    try #require(children.count == Self.prefixedRootChildren)
    #expect(children[0].matches("urn:d", "y"))
    #expect(children[1].matches("urn:a", "z"))
    #expect(children[0].attribute("k") == nil, "a prefixed attribute is namespaced")
    #expect(children[0].parent == root)
  }

  @Test
  internal func spansCoverTheElementExactly() throws {
    let text = #"<?xml version="1.0"?><r><c a="v">t</c><e/></r>"#
    let document = try Self.parse(text)
    let bytes = Data(text.utf8)
    let spans = document.allElements().map { element in
      String(bytes: bytes[element.span], encoding: .utf8)
    }
    #expect(spans == [#"<r><c a="v">t</c><e/></r>"#, #"<c a="v">t</c>"#, "<e/>"])
  }

  @Test
  internal func referencesCommentsAndCdataAreResolved() throws {
    let document = try Self.parse("<r>&amp;&lt;&#x41;&#66;<!-- c --><![CDATA[<raw>]]>\r\n</r>")
    #expect(document.root.text == "&<AB<raw>\n")
  }

  @Test
  internal func exoticConstructsAreRefused() {
    #expect(Self.refusal("<!DOCTYPE r><r/>") == .unsupported("document type declaration"))
    #expect(Self.refusal("<r><!DOCTYPE r></r>") == .unsupported("document type declaration"))
    #expect(Self.refusal("<r>&custom;</r>") == .unsupported("entity reference"))
    #expect(Self.refusal("<r a='&custom;'/>") == .unsupported("entity reference"))
    #expect(
      Self.refusal(#"<?xml version="1.0" encoding="ISO-8859-1"?><r/>"#)
        == .unsupported("an encoding other than UTF-8"))
    for malformed in [
      "<p:r/>", "<r a='v' a='w'/>", "<r></s>", "<r/><s/>", "<r>]]></r>", "<r><!-- a -- b --></r>",
      "<r a=v/>", "<r xmlns:p=''/>", "<r xmlns:xmlns='urn:x'/>", "<r xmlns:xml='urn:x'/>",
      "<r xmlns='relative/path'/>", "<r xmlns:p='../up'/>", "<r>&#0;</r>", "", "text",
      "<r Id='a'><c Id='a'/></r>",
    ] {
      guard case .malformed = Self.refusal(malformed) else {
        Issue.record("\(malformed) was not refused as malformed")
        continue
      }
    }
    #expect(
      (try? XmlDocument(Data([UInt8.max]))) == nil
    )
  }

  @Test
  internal func absoluteNamespacesAndTheUndeclaredDefaultPass() throws {
    for accepted in [
      "<r xmlns='urn:x' xmlns:p='http://example.org/p'><c xmlns=''/></r>",
      "<r xmlns:p='urn:example:p'/>",
    ] {
      _ = try Self.parse(accepted)
    }
  }

  @Test
  internal func nestingDeeperThanTheBoundIsRefused() {
    let depth = XmlParser.maximumDepth + 1
    let opened = String(repeating: "<r>", count: depth)
    let closed = String(repeating: "</r>", count: depth)
    #expect(Self.refusal(opened + closed) == .tooDeep)
  }

  @Test
  internal func exclusiveCanonicalisationRendersVisiblyUtilisedPrefixes() throws {
    let document = try Self.parse(Self.prefixedRoot)
    #expect(
      try Self.canonical(document.root, .exclusive)
        == #"<a:x xmlns:a="urn:a"><y xmlns="urn:d" a:k="v"></y><a:z></a:z></a:x>"#)
  }

  @Test
  internal func inclusiveCanonicalisationRendersEveryNamespaceInScope() throws {
    let document = try Self.parse(Self.prefixedRoot)
    #expect(
      try Self.canonical(document.root, .inclusive)
        == #"<a:x xmlns="urn:d" xmlns:a="urn:a"><y a:k="v"></y><a:z></a:z></a:x>"#)
  }

  @Test
  internal func attributesSortByNamespaceThenNameAndEscape() throws {
    let document = try Self.parse(#"<r b="2" a="1" xmlns:p="urn:p" p:a="&lt;&quot;&#9;"/>"#)
    #expect(
      try Self.canonical(document.root, .exclusive)
        == #"<r xmlns:p="urn:p" a="1" b="2" p:a="&lt;&quot;&#x9;"></r>"#)
  }

  @Test
  internal func textEscapesAmpersandAngleBracketsAndCarriageReturn() throws {
    let document = try Self.parse("<r>a > b &amp; c &#xD;<![CDATA[<]]></r>")
    #expect(try Self.canonical(document.root, .exclusive) == "<r>a &gt; b &amp; c &#xD;&lt;</r>")
  }

  @Test
  internal func commentsFollowTheMethodAndInstructionsStay() throws {
    let document = try Self.parse("<r><!--c--><?pi data?><?empty?></r>")
    #expect(try Self.canonical(document.root, .exclusive) == "<r><?pi data?><?empty?></r>")
    let retained = XmlCanonicalization(algorithm: .exclusive(.empty), comments: .retained)
    #expect(try Self.canonical(document.root, retained) == "<r><!--c--><?pi data?><?empty?></r>")
  }

  @Test
  internal func anOmittedSubtreeIsLeftOut() throws {
    let document = try Self.parse("<r><a/><s><t/></s><b/></r>")
    let signature = try Self.named(document, "s")
    #expect(
      try Self.canonical(document.root, .exclusive, omitting: signature)
        == "<r><a></a><b></b></r>")
  }

  @Test
  internal func theApexInheritsXmlAttributesOnlyInclusively() throws {
    let document = try Self.parse(
      #"<r xml:lang="en" xml:space="preserve"><c xml:space="default"/></r>"#)
    let child = try Self.named(document, "c")
    #expect(try Self.canonical(child, .exclusive) == #"<c xml:space="default"></c>"#)
    #expect(try Self.canonical(child, .inclusive) == #"<c xml:lang="en" xml:space="default"></c>"#)
    let inclusive11 = XmlCanonicalization(algorithm: .canonical11, comments: .omitted)
    #expect(try Self.canonical(child, inclusive11) == #"<c xml:lang="en" xml:space="default"></c>"#)
  }

  @Test
  internal func anApexBelowAnXmlBaseIsRefusedUnderCanonical11() throws {
    let document = try Self.parse(#"<r xml:base="http://example.org/"><c/></r>"#)
    let child = try Self.named(document, "c")
    let inclusive11 = XmlCanonicalization(algorithm: .canonical11, comments: .omitted)
    #expect(XmlCanonicalizer.canonicalize(child, method: inclusive11, omitting: nil) == nil)
    #expect(try Self.canonical(child, .inclusive) == #"<c xml:base="http://example.org/"></c>"#)
  }

  @Test
  internal func thePrefixListRendersTheDefaultNamespaceInScope() throws {
    let document = try Self.parse(#"<r xmlns="urn:d"><p:c xmlns:p="urn:p"/></r>"#)
    let child = try Self.named(document, "c")
    let listed = try #require(XmlCanonicalization.InclusivePrefixes(prefixList: "#default  p"))
    let method = XmlCanonicalization(algorithm: .exclusive(listed), comments: .omitted)
    #expect(try Self.canonical(child, method) == #"<p:c xmlns="urn:d" xmlns:p="urn:p"></p:c>"#)
    #expect(try Self.canonical(child, .exclusive) == #"<p:c xmlns:p="urn:p"></p:c>"#)
    #expect(XmlCanonicalization.InclusivePrefixes(prefixList: "a:b") == nil)
  }

  @Test
  internal func theUndeclaredDefaultIsRenderedUnderAParentWithOne() throws {
    let document = try Self.parse(#"<r xmlns="urn:d"><c xmlns=""><d/></c></r>"#)
    #expect(
      try Self.canonical(document.root, .inclusive)
        == #"<r xmlns="urn:d"><c xmlns=""><d></d></c></r>"#)
    #expect(
      try Self.canonical(document.root, .exclusive)
        == #"<r xmlns="urn:d"><c xmlns=""><d></d></c></r>"#)
  }

  @Test
  internal func attributeValuesAreNormalised() throws {
    let document = try Self.parse("<r a=\"x\n y\r\nz&#10;\"/>")
    #expect(document.root.attribute("a") == "x  y z\n")
  }

  @Test
  internal func aMethodElementNamesItsAlgorithmAndPrefixList() throws {
    let document = try Self.parse(
      #"<ds:SignedInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">"#
        + #"<ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#">"#
        + #"<ec:InclusiveNamespaces xmlns:ec="http://www.w3.org/2001/10/xml-exc-c14n#" "#
        + #"PrefixList="ds"/></ds:CanonicalizationMethod>"#
        + #"<ds:Transform Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>"#
        + #"<ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>"#
        + "</ds:SignedInfo>")
    let methods = document.root.children
    let listed = try #require(XmlCanonicalization.InclusivePrefixes(prefixList: "ds"))
    #expect(
      XmlCanonicalization(method: methods[0])
        == XmlCanonicalization(algorithm: .exclusive(listed), comments: .omitted))
    #expect(XmlCanonicalization(method: methods[1]) == .inclusive)
    #expect(XmlCanonicalization(method: methods[Self.prefixedRootChildren]) == nil)
  }
}
