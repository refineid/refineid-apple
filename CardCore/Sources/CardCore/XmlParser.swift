// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One pass over a document's UTF-8 bytes into `XmlDocument.Element`s.
///
/// The markup is ASCII, so the scan runs over bytes; character data is
/// decoded where it is collected, and every character is checked
/// against the XML `Char` production (XML 1.0 section 2.2).
internal struct XmlParser {
  /// A name as written: optional prefix and local part.
  internal struct QualifiedName {
    /// The part before the colon.
    internal let prefix: String?

    /// The part after it, or the whole name.
    internal let localName: String
  }

  /// An attribute as written, before namespace resolution.
  internal struct RawAttribute {
    /// The name.
    internal let name: QualifiedName

    /// The normalised value.
    internal let value: String
  }

  /// Deepest element nesting accepted.
  ///
  /// A signature file nests about ten levels deep and a trusted list
  /// about twelve; the bound keeps the recursive canonicaliser's stack
  /// small whatever the input.
  internal static let maximumDepth = 128

  /// Most nodes a document may hold: elements, text runs, comments and
  /// processing instructions together.
  ///
  /// The same bound as refineid-core's reader; it keeps a hostile
  /// document from growing the tree without limit.
  internal static let maximumNodes = 1 << 18

  /// Opens an XML declaration (XML 1.0 section 2.8).
  internal static let xmlDeclarationOpen = Data("<?xml".utf8)

  /// Opens a document type declaration (XML 1.0 section 2.8).
  internal static let doctypeOpen = Data("<!DOCTYPE".utf8)

  /// Opens a comment (XML 1.0 section 2.5).
  internal static let commentOpen = Data("<!--".utf8)

  /// Closes a comment.
  internal static let commentClose = Data("-->".utf8)

  /// Opens a CDATA section (XML 1.0 section 2.7).
  internal static let cdataOpen = Data("<![CDATA[".utf8)

  /// Closes a CDATA section.
  internal static let cdataClose = Data("]]>".utf8)

  /// Opens a processing instruction (XML 1.0 section 2.6).
  internal static let instructionOpen = Data("<?".utf8)

  /// Closes a processing instruction or the XML declaration.
  internal static let instructionClose = Data("?>".utf8)

  /// Opens an end tag (XML 1.0 section 3.1).
  internal static let endTagOpen = Data("</".utf8)

  /// Closes an empty-element tag (XML 1.0 section 3.1).
  internal static let emptyTagClose = Data("/>".utf8)

  /// The encoding name the XML declaration may carry (XML 1.0 section
  /// 4.3.3).
  internal static let encodingUtf8 = "UTF-8"

  /// Prefix of a hexadecimal character reference (XML 1.0 section 4.1).
  internal static let hexadecimalReferencePrefix = "#x"

  /// Prefix of a decimal character reference.
  internal static let decimalReferencePrefix = "#"

  /// The XML whitespace bytes (XML 1.0 section 2.3 production 3).
  internal static let whitespace: Set<UInt8> = [
    UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
  ]

  internal static let tagOpen = UInt8(ascii: "<")
  internal static let tagClose = UInt8(ascii: ">")
  internal static let ampersand = UInt8(ascii: "&")
  internal static let semicolon = UInt8(ascii: ";")
  internal static let equals = UInt8(ascii: "=")
  internal static let colon = UInt8(ascii: ":")
  internal static let carriageReturn = UInt8(ascii: "\r")
  internal static let lineFeed = UInt8(ascii: "\n")
  internal static let tab = UInt8(ascii: "\t")
  internal static let space = UInt8(ascii: " ")
  internal static let doubleQuote = UInt8(ascii: "\"")
  internal static let singleQuote = UInt8(ascii: "'")
  internal static let hyphen = UInt8(ascii: "-")
  internal static let underscore = UInt8(ascii: "_")
  internal static let period = UInt8(ascii: ".")

  /// The whole source, indexed from zero.
  internal let bytes: Data

  /// The byte offset of the next unread byte.
  internal var position = 0

  /// The elements parsed so far.
  internal var elements: [XmlDocument.Element] = []

  /// The open elements, innermost last.
  internal var open: [Int] = []

  /// Every `Id` attribute value seen so far.
  internal var identifiers: Set<String> = []

  /// Nodes created so far, bounded by `maximumNodes`.
  internal var nodes = 0

  /// The next unread byte.
  internal var peek: UInt8? {
    position < bytes.count ? bytes[position] : nil
  }

  /// Whether the whole source has been read.
  internal var isAtEnd: Bool { position >= bytes.count }

  /// A parser at the start of `bytes`, which are copied so they index
  /// from zero.
  internal init(bytes: Data) {
    self.bytes = Data(bytes)
  }

  /// Every element of `source`, in document order.
  ///
  /// Throws `XmlReadError` when the bytes are not UTF-8, not
  /// well-formed, use a refused feature, or exceed the bounds.
  internal static func parse(_ source: Data) throws -> [XmlDocument.Element] {
    guard String(data: source, encoding: .utf8) != nil else { throw XmlReadError.notUtf8 }
    var parser = Self(bytes: source)
    return try parser.document()
  }

  /// Whether `scalar` is an XML `Char` (XML 1.0 section 2.2
  /// production 2).
  internal static func isXmlCharacter(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case XmlValues.tabScalar, XmlValues.lineFeedScalar, XmlValues.carriageReturnScalar:
      true

    case XmlValues.characterRange1, XmlValues.characterRange2, XmlValues.characterRange3:
      true

    default:
      false
    }
  }

  /// Whether `token` occurs in `bytes` at `offset`; the first byte is
  /// compared alone because almost every offset of a list fails on it.
  private static func occurs(_ token: Data, in bytes: Data, at offset: Int) -> Bool {
    guard offset < bytes.count, bytes[offset] == token.first else { return false }
    return bytes[offset...].starts(with: token)
  }

  /// Whether `byte` may start a name.
  ///
  /// An ASCII letter, an underscore, or any byte of a non-ASCII
  /// character (Namespaces in XML 1.0 section 3 over XML 1.0 section
  /// 2.3 `NameStartChar`, colon excluded). Every non-ASCII character is
  /// accepted; the ASCII subset is exact.
  internal static func isNameStart(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
      || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
      || byte == Self.underscore
      || byte >= XmlValues.firstNonAsciiByte
  }

  /// Whether `byte` may continue a name.
  internal static func isNameCharacter(_ byte: UInt8) -> Bool {
    Self.isNameStart(byte)
      || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
      || byte == Self.hyphen
      || byte == Self.period
  }

  /// End-of-line handling (XML 1.0 section 2.11): CR LF and a lone CR
  /// both become LF.
  internal static func normalisedLineEnds(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  /// `slice` as text, every character inside the XML `Char` set.
  internal static func validated(_ slice: Data) throws -> String {
    guard
      let text = String(bytes: slice, encoding: .utf8),
      text.unicodeScalars.allSatisfy(Self.isXmlCharacter)
    else {
      throw XmlReadError.malformed("character outside the XML Char set")
    }
    return text
  }

  /// Whether the unread bytes start with `token`.
  internal func at(_ token: Data) -> Bool {
    Self.occurs(token, in: bytes, at: position)
  }

  /// Consumes `token` if the unread bytes start with it.
  internal mutating func eat(_ token: Data) -> Bool {
    guard at(token) else { return false }
    position += token.count
    return true
  }

  /// Consumes `token` or fails with `what`.
  internal mutating func expect(_ token: Data, _ what: String) throws {
    guard eat(token) else { throw XmlReadError.malformed(what) }
  }

  /// Consumes XML whitespace and reports whether there was any.
  internal mutating func skipWhitespace() -> Bool {
    let start = position
    while let byte = peek, Self.whitespace.contains(byte) {
      position += 1
    }
    return position != start
  }

  /// Consumes the bytes up to `close` and `close` itself, returning the
  /// bytes before it.
  internal mutating func until(_ close: Data, _ what: String) throws -> Data {
    var offset = position
    while offset + close.count <= bytes.count {
      if Self.occurs(close, in: bytes, at: offset) {
        let body = bytes[position..<offset]
        position = offset + close.count
        return body
      }
      offset += 1
    }
    throw XmlReadError.malformed(what)
  }

  /// A run of name bytes, colons included.
  internal mutating func nameToken() throws -> String {
    let start = position
    guard let first = peek, Self.isNameStart(first) else {
      throw XmlReadError.malformed("name expected")
    }
    position += 1
    while let byte = peek, Self.isNameCharacter(byte) || byte == Self.colon {
      position += 1
    }
    guard let token = String(bytes: bytes[start..<position], encoding: .utf8) else {
      throw XmlReadError.malformed("name expected")
    }
    return token
  }

  /// A `QName` (Namespaces in XML 1.0 section 4): one optional prefix
  /// and a local part, both `NCName`s.
  internal mutating func qualifiedName() throws -> QualifiedName {
    let token = try nameToken()
    let parts = token.split(separator: ":", omittingEmptySubsequences: false)
    switch parts.count {
    case 1:
      return QualifiedName(prefix: nil, localName: token)

    case XmlValues.qualifiedNameParts:
      guard
        let prefixStart = parts[0].utf8.first, Self.isNameStart(prefixStart),
        let localStart = parts[1].utf8.first, Self.isNameStart(localStart)
      else {
        throw XmlReadError.malformed("empty name part")
      }
      return QualifiedName(prefix: String(parts[0]), localName: String(parts[1]))

    default:
      throw XmlReadError.malformed("name with more than one colon")
    }
  }

  /// Counts one more node against `maximumNodes`.
  internal mutating func countNode() throws {
    nodes += 1
    guard nodes <= Self.maximumNodes else { throw XmlReadError.tooManyNodes }
  }
}
