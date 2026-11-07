// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The content of the document element: child elements, character
/// data, CDATA sections, comments, processing instructions and
/// references.
extension XmlParser {
  /// The `Char` the digits of a character reference name.
  private static func characterReference(_ digits: Substring, radix: Int) -> Unicode.Scalar? {
    guard
      !digits.isEmpty,
      digits.allSatisfy({ character in character.isASCII && character.isHexDigit }),
      let value = UInt32(digits, radix: radix),
      let scalar = Unicode.Scalar(value),
      Self.isXmlCharacter(scalar)
    else {
      return nil
    }
    return scalar
  }

  /// The document element and everything inside it.
  internal mutating func content() throws {
    try startTag()
    while let current = open.last {
      if eat(Self.endTagOpen) {
        try endTag(current)
      } else if eat(Self.commentOpen) {
        try pushNode(current, .comment(try commentBody()))
      } else if eat(Self.cdataOpen) {
        let text = try Self.validated(try until(Self.cdataClose, "unterminated CDATA"))
        try pushText(current, Self.normalisedLineEnds(text))
      } else if at(Self.doctypeOpen) {
        throw XmlReadError.unsupported("document type declaration")
      } else if at(Self.instructionOpen) {
        try pushNode(current, try processingInstruction())
      } else if peek == Self.tagOpen {
        try startTag()
      } else {
        try pushText(current, try characterData())
      }
    }
  }

  /// A reference starting at `&` (XML 1.0 section 4.1): one of the five
  /// predefined entities or a character reference.
  internal mutating func reference() throws -> Unicode.Scalar {
    try expect(Data([Self.ampersand]), "reference")
    let body = try Self.validated(try until(Data([Self.semicolon]), "unterminated reference"))
    let resolved: Unicode.Scalar?
    switch body {
    case "amp":
      resolved = "&"

    case "lt":
      resolved = "<"

    case "gt":
      resolved = ">"

    case "quot":
      resolved = "\""

    case "apos":
      resolved = "'"

    default:
      if body.hasPrefix(Self.hexadecimalReferencePrefix) {
        resolved = Self.characterReference(
          body.dropFirst(Self.hexadecimalReferencePrefix.count), radix: XmlValues.hexadecimalRadix)
      } else if body.hasPrefix(Self.decimalReferencePrefix) {
        resolved = Self.characterReference(
          body.dropFirst(Self.decimalReferencePrefix.count), radix: XmlValues.decimalRadix)
      } else {
        throw XmlReadError.unsupported("entity reference")
      }
    }
    guard let scalar = resolved else { throw XmlReadError.malformed("character reference") }
    return scalar
  }

  /// Appends `node` to the children of the element at `parent`.
  internal mutating func pushNode(_ parent: Int, _ node: XmlDocument.Node) throws {
    try countNode()
    elements[parent].children.append(node)
  }

  /// Appends character data to `parent`, merging with a preceding text
  /// child.
  internal mutating func pushText(_ parent: Int, _ text: String) throws {
    guard !text.isEmpty else { return }
    if case .text(let previous) = elements[parent].children.last {
      elements[parent].children[elements[parent].children.count - 1] = .text(previous + text)
      return
    }
    try countNode()
    elements[parent].children.append(.text(text))
  }

  /// Character data up to the next markup.
  private mutating func characterData() throws -> String {
    var out = Data()
    while true {
      guard let byte = peek else { throw XmlReadError.malformed("unterminated element") }
      switch byte {
      case Self.tagOpen:
        return try Self.validated(out)

      case Self.ampersand:
        out.append(contentsOf: String(try reference()).utf8)

      case Self.carriageReturn:
        position += 1
        _ = eat(Data([Self.lineFeed]))
        out.append(Self.lineFeed)

      default:
        guard !at(Self.cdataClose) else {
          throw XmlReadError.malformed("]]> in character data")
        }
        out.append(byte)
        position += 1
      }
    }
  }
}
