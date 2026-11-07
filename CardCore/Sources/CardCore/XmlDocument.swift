// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A small XML reader for signature files and trusted lists, whose
/// elements `XmlCanonicalizer` renders under Canonical XML 1.0,
/// Canonical XML 1.1 or Exclusive XML Canonicalization 1.0.
///
/// The reader accepts the XML an XAdES signature or an ETSI TS 119 612
/// list is made of: elements with namespaces, attributes, character
/// data, CDATA sections, the five predefined entity references and
/// character references, comments and processing instructions. Every
/// element records the byte range it occupies in the source. A document
/// type declaration, any other entity reference, an encoding other than
/// UTF-8 and every namespace misuse are refused: the producers write
/// none of them, and a reader that resolves less than the producer wrote
/// would digest different bytes. Two elements carrying the same `Id`
/// are refused too, so a same-document reference names one element or
/// none (W3C XML Signature 1.1 section 4.4.3.3).
///
/// Conformance: W3C XML 1.0 (Fifth Edition) sections 2.2, 2.11, 3.3.3,
/// 4.1 and 4.6; W3C Namespaces in XML 1.0 (Third Edition) sections 3
/// and 6.
internal final class XmlDocument: Sendable {
  /// One parsed attribute, namespace declarations excluded.
  internal struct Attribute: Sendable, Equatable {
    /// The prefix as written.
    internal let prefix: String?

    /// The local part of the name.
    internal let localName: String

    /// The namespace the prefix resolves to; nil for an unprefixed
    /// attribute, which is in no namespace.
    internal let namespace: String?

    /// The normalised value, references resolved.
    internal let value: String

    /// Whether this is the `xml:` attribute named `localName`.
    internal func isXml(_ localName: String) -> Bool {
      namespace == XmlDocument.namespaceXml && self.localName == localName
    }
  }

  /// One namespace declaration made on an element.
  internal struct Declaration: Sendable, Equatable {
    /// The declared prefix; nil for the default namespace.
    internal let prefix: String?

    /// The namespace name; empty only when undeclaring the default.
    internal let uri: String
  }

  /// One child of an element.
  internal enum Node: Sendable, Equatable {
    /// A comment's text.
    case comment(String)

    /// A child element, by index into the document's elements.
    case element(Int)

    /// A processing instruction's target and data.
    case processingInstruction(target: String, data: String)

    /// Character data, references resolved and line ends normalised.
    case text(String)
  }

  /// One parsed element.
  internal struct Element: Sendable {
    /// The prefix as written.
    internal var prefix: String?

    /// The local part of the name.
    internal var localName: String

    /// The namespace the element is in, if any.
    internal var namespace: String?

    /// The attributes, in source order.
    internal var attributes: [Attribute]

    /// The namespace declarations made on this element.
    internal var declarations: [Declaration]

    /// The children, in document order.
    internal var children: [Node]

    /// The enclosing element.
    internal var parent: Int?

    /// The bytes of the source the element occupies, start tag
    /// through end tag.
    internal var span: Range<Int>
  }

  /// The namespace the `xml` prefix is bound to by definition
  /// (Namespaces in XML 1.0 section 3).
  internal static let namespaceXml = "http://www.w3.org/XML/1998/namespace"

  /// The namespace the `xmlns` prefix is bound to by definition.
  internal static let namespaceXmlns = "http://www.w3.org/2000/xmlns/"

  /// The prefix bound to `namespaceXml`.
  internal static let prefixXml = "xml"

  /// The attribute name, or prefix, of a namespace declaration.
  internal static let prefixXmlns = "xmlns"

  /// The identifier attribute a same-document reference names (W3C XML
  /// Signature 1.1 section 4.4.3.3, EN 319 132-1 clause 4.2).
  internal static let attributeId = "Id"

  /// Every element, in document order; the document element first.
  private let elements: [Element]

  /// The document element.
  internal var root: XmlElement { XmlElement(document: self, index: 0) }

  /// How many elements the document has.
  internal var elementCount: Int { elements.count }

  /// Parses a complete document.
  ///
  /// Throws `XmlReadError` when the bytes are not UTF-8, not
  /// well-formed, use a refused feature, or exceed the reader's bounds.
  internal init(_ source: Data) throws {
    let parsed = try XmlParser.parse(source)
    guard !parsed.isEmpty else { throw XmlReadError.malformed("no document element") }
    elements = parsed
  }

  /// The element at `index`, which must be below `elementCount`.
  internal func element(at index: Int) -> Element {
    elements[index]
  }

  /// Every element, in document order.
  internal func allElements() -> [XmlElement] {
    elements.indices.map { index in XmlElement(document: self, index: index) }
  }

  /// The one element carrying `Id` equal to `identifier`, or nil.
  internal func element(withId identifier: String) -> XmlElement? {
    allElements().first { element in
      element.attribute(Self.attributeId) == identifier
    }
  }
}
