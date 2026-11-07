// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Start tags, their attributes and namespace declarations, and end
/// tags.
extension XmlParser {
  /// The attributes of a start tag sorted into namespace declarations
  /// and the rest.
  private struct SortedAttributes {
    /// The namespace declarations, in source order.
    var declarations: [XmlDocument.Declaration] = []

    /// The other attributes, in source order.
    var plain: [RawAttribute] = []
  }

  /// Whether `uri` opens with a scheme: a letter, then letters, digits,
  /// `+`, `-` or `.`, and a colon (RFC 3986 section 3.1).
  internal static func isAbsoluteUri(_ uri: String) -> Bool {
    guard let colon = uri.firstIndex(of: ":") else { return false }
    let scheme = uri[..<colon]
    guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
    return scheme.allSatisfy { character in
      character.isASCII && (character.isLetter || character.isNumber || "+-.".contains(character))
    }
  }

  /// The namespace declarations among `raw`, checked as Namespaces in
  /// XML 1.0 section 3 requires, and the other attributes.
  private static func sorted(_ raw: [RawAttribute]) throws -> SortedAttributes {
    var sorted = SortedAttributes()
    for attribute in raw {
      switch (attribute.name.prefix, attribute.name.localName) {
      case (nil, XmlDocument.prefixXmlns):
        try Self.checkDeclaredUri(attribute.value, allowsEmpty: true)
        sorted.declarations.append(XmlDocument.Declaration(prefix: nil, uri: attribute.value))

      case (XmlDocument.prefixXmlns, XmlDocument.prefixXml):
        guard attribute.value == XmlDocument.namespaceXml else {
          throw XmlReadError.malformed("xml prefix rebound")
        }

      case (XmlDocument.prefixXmlns, XmlDocument.prefixXmlns):
        throw XmlReadError.malformed("xmlns prefix declared")

      case (XmlDocument.prefixXmlns, let prefix):
        try Self.checkDeclaredUri(attribute.value, allowsEmpty: false)
        sorted.declarations.append(XmlDocument.Declaration(prefix: prefix, uri: attribute.value))

      default:
        sorted.plain.append(attribute)
      }
    }
    let prefixes = sorted.declarations.map(\.prefix)
    guard Set(prefixes).count == prefixes.count else {
      throw XmlReadError.malformed("duplicate namespace declaration")
    }
    return sorted
  }

  /// A declared namespace name: never a reserved namespace, never
  /// relative (Canonical XML 1.0 section 2.1 fails on one), and empty
  /// only when undeclaring the default.
  private static func checkDeclaredUri(_ uri: String, allowsEmpty: Bool) throws {
    guard uri != XmlDocument.namespaceXml, uri != XmlDocument.namespaceXmlns else {
      throw XmlReadError.malformed("reserved namespace declared")
    }
    if uri.isEmpty {
      guard allowsEmpty else { throw XmlReadError.malformed("prefix undeclared") }
      return
    }
    guard Self.isAbsoluteUri(uri) else { throw XmlReadError.malformed("relative namespace URI") }
  }

  /// A start tag or empty-element tag at `<`.
  internal mutating func startTag() throws {
    guard open.count < Self.maximumDepth else { throw XmlReadError.tooDeep }
    try countNode()
    let start = position
    try expect(Data([Self.tagOpen]), "start tag")
    let name = try qualifiedName()
    guard name.prefix != XmlDocument.prefixXmlns else {
      throw XmlReadError.malformed("element in the xmlns namespace")
    }
    let (raw, empty) = try rawAttributes()
    let sorted = try Self.sorted(raw)
    let index = elements.count
    let parent = open.last
    elements.append(
      XmlDocument.Element(
        prefix: name.prefix, localName: name.localName, namespace: nil, attributes: [],
        declarations: sorted.declarations, children: [], parent: parent, span: start..<start))
    let namespace: String?
    if let prefix = name.prefix {
      guard let resolved = resolve(prefix, at: index) else {
        throw XmlReadError.malformed("undeclared element prefix")
      }
      namespace = resolved
    } else {
      namespace = resolve(nil, at: index)
    }
    elements[index].namespace = namespace
    elements[index].attributes = try resolvedAttributes(sorted.plain, at: index)
    elements[index].span = start..<position
    if let parent {
      elements[parent].children.append(.element(index))
    }
    if !empty {
      open.append(index)
    }
  }

  /// What `prefix` resolves to at the element at `index`: its
  /// declarations, then its ancestors'.
  ///
  /// Nil for the undeclared default namespace, and for a prefix no
  /// element declares.
  internal func resolve(_ prefix: String?, at index: Int) -> String? {
    if prefix == XmlDocument.prefixXml { return XmlDocument.namespaceXml }
    var current: Int? = index
    while let element = current {
      if let declaration = elements[element].declarations.first(where: { $0.prefix == prefix }) {
        return declaration.uri.isEmpty ? nil : declaration.uri
      }
      current = elements[element].parent
    }
    return nil
  }

  /// An end tag after its `</`, which must name the open element.
  internal mutating func endTag(_ current: Int) throws {
    let name = try qualifiedName()
    _ = skipWhitespace()
    try expect(Data([Self.tagClose]), "unterminated end tag")
    guard
      elements[current].prefix == name.prefix,
      elements[current].localName == name.localName
    else {
      throw XmlReadError.malformed("end tag does not match the start tag")
    }
    elements[current].span = elements[current].span.lowerBound..<position
    open.removeLast()
  }

  /// The attributes as written and whether the tag closed itself.
  private mutating func rawAttributes() throws -> (attributes: [RawAttribute], empty: Bool) {
    var raw: [RawAttribute] = []
    while true {
      let spaced = skipWhitespace()
      if eat(Self.emptyTagClose) { return (raw, true) }
      if eat(Data([Self.tagClose])) { return (raw, false) }
      guard spaced else {
        throw XmlReadError.malformed("attributes must be separated by whitespace")
      }
      let name = try qualifiedName()
      _ = skipWhitespace()
      try expect(Data([Self.equals]), "attribute without a value")
      _ = skipWhitespace()
      raw.append(RawAttribute(name: name, value: try attributeValue()))
    }
  }

  /// The attributes of the element at `index` with their namespaces
  /// resolved, no two alike, and its `Id` recorded as unique.
  private mutating func resolvedAttributes(
    _ plain: [RawAttribute],
    at index: Int
  ) throws -> [XmlDocument.Attribute] {
    var attributes: [XmlDocument.Attribute] = []
    for attribute in plain {
      var namespace: String?
      if let prefix = attribute.name.prefix {
        guard let resolved = resolve(prefix, at: index) else {
          throw XmlReadError.malformed("undeclared attribute prefix")
        }
        namespace = resolved
      }
      let localName = attribute.name.localName
      guard
        !attributes.contains(where: { $0.localName == localName && $0.namespace == namespace })
      else {
        throw XmlReadError.malformed("duplicate attribute")
      }
      if namespace == nil, localName == XmlDocument.attributeId {
        guard identifiers.insert(attribute.value).inserted else {
          throw XmlReadError.malformed("duplicate Id")
        }
      }
      attributes.append(
        XmlDocument.Attribute(
          prefix: attribute.name.prefix, localName: localName, namespace: namespace,
          value: attribute.value))
    }
    return attributes
  }

  /// A quoted attribute value, normalised as XML 1.0 section 3.3.3 does
  /// for CDATA.
  ///
  /// Each literal whitespace character becomes a space, a CR LF pair
  /// one space, and references are resolved without normalisation.
  private mutating func attributeValue() throws -> String {
    guard let quote = peek, quote == Self.doubleQuote || quote == Self.singleQuote else {
      throw XmlReadError.malformed("attribute value must be quoted")
    }
    position += 1
    var out = Data()
    while true {
      guard let byte = peek else { throw XmlReadError.malformed("unterminated attribute value") }
      switch byte {
      case quote:
        position += 1
        return try Self.validated(out)

      case Self.tagOpen:
        throw XmlReadError.malformed("< in an attribute value")

      case Self.ampersand:
        out.append(contentsOf: String(try reference()).utf8)

      case Self.carriageReturn:
        position += 1
        _ = eat(Data([Self.lineFeed]))
        out.append(Self.space)

      case Self.lineFeed, Self.tab:
        position += 1
        out.append(Self.space)

      default:
        out.append(byte)
        position += 1
      }
    }
  }
}
