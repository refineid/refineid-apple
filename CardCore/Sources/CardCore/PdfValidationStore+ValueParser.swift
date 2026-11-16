// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Parsing the small PDF value subset used by document security stores.
extension PdfValidationStore {
  /// Numeric and escaped-name tokens shared by the value parser.
  internal enum ValueLexemes {
    /// Digits following the marker in one escaped name byte.
    private static let escapedNameDigits = 2

    /// Bytes occupied by one name escape.
    private static let escapedNameLength = 3

    /// Number base of a name escape.
    private static let hexRadix = 16

    /// Bytes occupied by the name's slash prefix.
    internal static let namePrefixLength = 1

    /// Decodes `#xx` escapes in a PDF name and drops the slash.
    internal static func decodedName(_ raw: Data) -> String? {
      var decoded = Data()
      var cursor = raw.startIndex + Self.namePrefixLength
      while cursor < raw.endIndex {
        if raw[cursor] == UInt8(ascii: "#"),
          cursor + Self.escapedNameDigits < raw.endIndex,
          let high = Self.hex(raw[cursor + 1]),
          let low = Self.hex(raw[cursor + Self.escapedNameDigits])
        {
          decoded.append(high * UInt8(Self.hexRadix) + low)
          cursor += Self.escapedNameLength
        } else {
          decoded.append(raw[cursor])
          cursor += Self.namePrefixLength
        }
      }
      return String(data: decoded, encoding: .isoLatin1)
    }

    /// A non-negative decimal token.
    internal static func unsignedInteger(_ data: Data) -> Int? {
      guard
        !data.isEmpty,
        data.allSatisfy({ byte in
          byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
        })
      else { return nil }
      return Int(Self.text(data))
    }

    /// Latin-1 preserves each PDF source byte as one scalar.
    internal static func text(_ data: Data) -> String {
      String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// One hexadecimal digit's value.
    private static func hex(_ byte: UInt8) -> UInt8? {
      let text = String(bytes: [byte], encoding: .ascii)
      return text.flatMap { UInt8($0, radix: Self.hexRadix) }
    }
  }

  /// A byte-oriented parser for dictionaries and indirect references.
  internal struct ValueParser {
    /// PDF delimiter octets.
    private static let delimiters = Data("()<>[]{}/%".utf8)

    /// The bytes being parsed.
    internal let bytes: Data

    /// The next unread byte.
    internal var offset = 0

    /// Starts at the beginning of `bytes`.
    internal init(_ bytes: Data) {
      self.bytes = bytes
    }

    /// Parses one complete indirect reference.
    internal static func reference(in text: String) throws -> StoreReference? {
      guard let data = text.data(using: .isoLatin1) else { return nil }
      var parser = Self(data)
      guard let reference = parser.reference() else { return nil }
      try parser.requireEnd()
      return reference
    }

    /// Parses one complete array containing only indirect references.
    internal static func referenceArray(in text: String) throws -> [StoreReference] {
      guard let data = text.data(using: .isoLatin1) else {
        throw PdfSigningError.structureUnreadable
      }
      var parser = Self(data)
      parser.skipTrivia()
      guard parser.consume("[") else {
        throw PdfSigningError.structureUnreadable
      }
      var references: [StoreReference] = []
      while true {
        parser.skipTrivia()
        if parser.consume("]") {
          try parser.requireEnd()
          return references
        }
        guard let reference = parser.reference() else {
          throw PdfSigningError.structureUnreadable
        }
        references.append(reference)
      }
    }

    /// A PDF token delimiter or whitespace octet.
    internal static func isDelimiter(_ byte: UInt8) -> Bool {
      Self.isWhitespace(byte) || Self.delimiters.contains(byte)
    }

    /// The whitespace octets ISO 32000 assigns syntactic meaning.
    private static func isWhitespace(_ byte: UInt8) -> Bool {
      byte == 0
        || byte == UInt8(ascii: "\t")
        || byte == UInt8(ascii: "\n")
        || byte == UInt8(ascii: "\u{000C}")
        || byte == UInt8(ascii: "\r")
        || byte == UInt8(ascii: " ")
    }

    /// Parses one dictionary and returns its entries and closing position.
    internal mutating func dictionary() throws -> (
      entries: [DictionaryEntry], closingOffset: Int
    ) {
      self.skipTrivia()
      guard self.consume("<<") else {
        throw PdfSigningError.structureUnreadable
      }
      var entries: [DictionaryEntry] = []
      var names: Set<String> = []
      while true {
        self.skipTrivia()
        let closingOffset = offset
        if self.consume(">>") {
          return (entries, closingOffset)
        }
        let name = try self.name()
        guard names.insert(name.decoded).inserted else {
          throw PdfSigningError.structureUnreadable
        }
        self.skipTrivia()
        let valueRange = try self.value()
        entries.append(
          DictionaryEntry(
            name: name.decoded,
            rawName: ValueLexemes.text(bytes.subdata(in: name.raw)),
            valueRange: valueRange
          )
        )
      }
    }

    /// Requires only whitespace or comments to remain.
    internal mutating func requireEnd() throws {
      self.skipTrivia()
      guard offset == bytes.count else {
        throw PdfSigningError.structureUnreadable
      }
    }

    /// One value, including a full indirect reference when present.
    private mutating func value() throws -> Range<Int> {
      let start = offset
      if self.has("<<") {
        _ = try self.dictionary()
      } else if self.consume("[") {
        try self.arrayRemainder()
      } else if self.consume("(") {
        try self.literalStringRemainder()
      } else if self.consume("<") {
        try self.hexStringRemainder()
      } else if self.has("/") {
        _ = try self.name()
      } else {
        let first = try self.atom()
        self.consumeReferenceTail(after: first)
      }
      return start..<offset
    }

    /// The remainder of an array after its opening bracket.
    private mutating func arrayRemainder() throws {
      while true {
        self.skipTrivia()
        if self.consume("]") { return }
        _ = try self.value()
      }
    }

    /// The remainder of a balanced literal string.
    private mutating func literalStringRemainder() throws {
      var depth = 1
      while offset < bytes.count {
        let byte = bytes[offset]
        offset += 1
        if byte == UInt8(ascii: "\\") {
          if offset < bytes.count { offset += 1 }
        } else if byte == UInt8(ascii: "(") {
          depth += 1
        } else if byte == UInt8(ascii: ")") {
          depth -= 1
          if depth == 0 { return }
        }
      }
      throw PdfSigningError.structureUnreadable
    }

    /// The remainder of a hexadecimal string.
    private mutating func hexStringRemainder() throws {
      while offset < bytes.count {
        let byte = bytes[offset]
        offset += 1
        if byte == UInt8(ascii: ">") { return }
      }
      throw PdfSigningError.structureUnreadable
    }

    /// A name token, decoded for comparison and retained for copying.
    internal mutating func name() throws -> (decoded: String, raw: Range<Int>) {
      let start = offset
      guard self.consume("/") else {
        throw PdfSigningError.structureUnreadable
      }
      while offset < bytes.count, !Self.isDelimiter(bytes[offset]) {
        offset += 1
      }
      guard offset > start + ValueLexemes.namePrefixLength else {
        throw PdfSigningError.structureUnreadable
      }
      let raw = start..<offset
      guard let decoded = ValueLexemes.decodedName(bytes.subdata(in: raw)) else {
        throw PdfSigningError.structureUnreadable
      }
      return (decoded, raw)
    }

    /// One non-delimiter token.
    internal mutating func atom() throws -> Range<Int> {
      let start = offset
      while offset < bytes.count, !Self.isDelimiter(bytes[offset]) {
        offset += 1
      }
      guard offset > start else {
        throw PdfSigningError.structureUnreadable
      }
      return start..<offset
    }

    /// Extends an integer value through its `generation R` tail.
    private mutating func consumeReferenceTail(after first: Range<Int>) {
      guard ValueLexemes.unsignedInteger(bytes.subdata(in: first)) != nil else {
        return
      }
      let valueEnd = offset
      self.skipTrivia()
      guard
        let second = try? self.atom(),
        ValueLexemes.unsignedInteger(bytes.subdata(in: second)) != nil
      else {
        offset = valueEnd
        return
      }
      self.skipTrivia()
      guard
        let marker = try? self.atom(),
        ValueLexemes.text(bytes.subdata(in: marker)) == "R"
      else {
        offset = valueEnd
        return
      }
    }

    /// One indirect reference at the current position.
    private mutating func reference() -> StoreReference? {
      self.skipTrivia()
      guard
        let numberRange = try? self.atom(),
        let number = ValueLexemes.unsignedInteger(bytes.subdata(in: numberRange))
      else { return nil }
      self.skipTrivia()
      guard
        let generationRange = try? self.atom(),
        let generation = ValueLexemes.unsignedInteger(
          bytes.subdata(in: generationRange)
        )
      else { return nil }
      self.skipTrivia()
      guard
        let marker = try? self.atom(),
        ValueLexemes.text(bytes.subdata(in: marker)) == "R"
      else { return nil }
      return StoreReference(number: number, generation: generation)
    }

    /// Skips PDF whitespace and end-of-line comments.
    internal mutating func skipTrivia() {
      while offset < bytes.count {
        if Self.isWhitespace(bytes[offset]) {
          offset += 1
          continue
        }
        guard bytes[offset] == UInt8(ascii: "%") else { return }
        while offset < bytes.count,
          bytes[offset] != UInt8(ascii: "\n"),
          bytes[offset] != UInt8(ascii: "\r")
        {
          offset += 1
        }
      }
    }

    /// Consumes an exact ASCII marker.
    internal mutating func consume(_ marker: String) -> Bool {
      guard self.has(marker) else { return false }
      offset += marker.utf8.count
      return true
    }

    /// Whether an exact ASCII marker is next.
    internal func has(_ marker: String) -> Bool {
      let encoded = Data(marker.utf8)
      guard offset + encoded.count <= bytes.count else { return false }
      return bytes[offset..<(offset + encoded.count)].elementsEqual(encoded)
    }
  }
}
