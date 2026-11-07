// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The document as a whole: prolog, one element, trailing misc.
extension XmlParser {
  /// Whether `<?xml` is followed by whitespace, which makes it the XML
  /// declaration rather than a processing instruction whose target
  /// starts with those letters.
  private var startsDeclaration: Bool {
    let after = position + Self.xmlDeclarationOpen.count
    return after < bytes.count && Self.whitespace.contains(bytes[after])
  }

  /// One pseudo-attribute of the XML declaration: `version` first,
  /// then `encoding` and `standalone`.
  private static func checkDeclarationField(_ name: String, value: String, first: Bool) throws {
    switch (name, first) {
    case ("version", true):
      return

    case ("encoding", false):
      guard value.caseInsensitiveCompare(Self.encodingUtf8) == .orderedSame else {
        throw XmlReadError.unsupported("an encoding other than UTF-8")
      }

    case ("standalone", false):
      return

    default:
      throw XmlReadError.malformed("XML declaration")
    }
  }

  /// The whole document.
  internal mutating func document() throws -> [XmlDocument.Element] {
    _ = eat(XmlValues.byteOrderMark)
    if at(Self.xmlDeclarationOpen), startsDeclaration {
      try xmlDeclaration()
    }
    try misc()
    if at(Self.doctypeOpen) {
      throw XmlReadError.unsupported("document type declaration")
    }
    guard peek == Self.tagOpen else { throw XmlReadError.malformed("no document element") }
    try content()
    try misc()
    guard isAtEnd else { throw XmlReadError.malformed("content after the document element") }
    return elements
  }

  /// Comments, processing instructions and whitespace outside the
  /// document element.
  internal mutating func misc() throws {
    while true {
      _ = skipWhitespace()
      if eat(Self.commentOpen) {
        _ = try commentBody()
      } else if at(Self.instructionOpen) {
        _ = try processingInstruction()
      } else {
        return
      }
    }
  }

  /// The rest of a comment after its opening; `--` may not occur in it
  /// (XML 1.0 section 2.5).
  internal mutating func commentBody() throws -> String {
    let body = try Self.validated(try until(Self.commentClose, "unterminated comment"))
    guard !body.contains("--"), !body.hasSuffix("-") else {
      throw XmlReadError.malformed("double hyphen in a comment")
    }
    return Self.normalisedLineEnds(body)
  }

  /// A processing instruction; its target may not be `xml` in any case
  /// (XML 1.0 section 2.6).
  internal mutating func processingInstruction() throws -> XmlDocument.Node {
    try expect(Self.instructionOpen, "processing instruction")
    let target = try nameToken()
    guard target.caseInsensitiveCompare(XmlDocument.prefixXml) != .orderedSame else {
      throw XmlReadError.malformed("misplaced XML declaration")
    }
    guard !target.contains(":") else {
      throw XmlReadError.malformed("colon in a processing instruction target")
    }
    let spaced = skipWhitespace()
    let data = try Self.validated(
      try until(Self.instructionClose, "unterminated processing instruction"))
    guard spaced || data.isEmpty else {
      throw XmlReadError.malformed("processing instruction target")
    }
    return .processingInstruction(target: target, data: Self.normalisedLineEnds(data))
  }

  /// The XML declaration: version and an encoding, when named, of
  /// UTF-8 (XML 1.0 sections 2.8 and 4.3.3).
  private mutating func xmlDeclaration() throws {
    try expect(Self.xmlDeclarationOpen, "XML declaration")
    let body = try until(Self.instructionClose, "unterminated XML declaration")
    var declaration = Self(bytes: body)
    var first = true
    while true {
      let spaced = declaration.skipWhitespace()
      if declaration.isAtEnd { break }
      guard spaced else { throw XmlReadError.malformed("XML declaration") }
      let name = try declaration.nameToken()
      _ = declaration.skipWhitespace()
      try declaration.expect(Data([Self.equals]), "XML declaration")
      _ = declaration.skipWhitespace()
      let value = try declaration.quotedLiteral()
      try Self.checkDeclarationField(name, value: value, first: first)
      first = false
    }
    guard !first else { throw XmlReadError.malformed("XML declaration without a version") }
  }

  /// A quoted literal with no references, for the XML declaration.
  private mutating func quotedLiteral() throws -> String {
    guard let quote = peek, quote == Self.doubleQuote || quote == Self.singleQuote else {
      throw XmlReadError.malformed("missing quote")
    }
    position += 1
    return try Self.validated(try until(Data([quote]), "unterminated literal"))
  }
}
