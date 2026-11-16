// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Token-safe scalar and array decoders built on `ValueParser`.
extension PdfValidationStore {
  /// Typed PDF value readers backed by `ValueParser`.
  internal enum TypedValues {
    /// Parses one unsigned decimal integer, refusing negative values,
    /// overflows, and indirect `N G R` references.
    internal static func unsignedInteger(in text: String) -> Int? {
      guard let data = text.data(using: .isoLatin1) else { return nil }
      var parser = ValueParser(data)
      parser.skipTrivia()
      guard
        let range = try? parser.atom(),
        let value = ValueLexemes.unsignedInteger(data.subdata(in: range)),
        (try? parser.requireEnd()) != nil
      else {
        return nil
      }
      return value
    }

    /// Parses a complete `[ n1 n2 ... ]` array of unsigned decimal
    /// integers, returning an empty list when `text` is not one.
    internal static func unsignedIntegerArray(in text: String) -> [Int] {
      guard let values = try? Self.strictUnsignedIntegerArray(in: text) else {
        return []
      }
      return values
    }

    /// Parses a complete `[ n1 n2 ... ]` array of unsigned decimal
    /// integers, throwing when malformed.
    internal static func strictUnsignedIntegerArray(
      in text: String
    ) throws -> [Int] {
      guard let data = text.data(using: .isoLatin1) else {
        throw PdfSigningError.structureUnreadable
      }
      var parser = ValueParser(data)
      parser.skipTrivia()
      guard parser.consume("[") else {
        throw PdfSigningError.structureUnreadable
      }
      var values: [Int] = []
      while true {
        parser.skipTrivia()
        if parser.consume("]") {
          try parser.requireEnd()
          return values
        }
        let token = try parser.atom()
        guard
          let value = ValueLexemes.unsignedInteger(data.subdata(in: token))
        else {
          throw PdfSigningError.structureUnreadable
        }
        values.append(value)
      }
    }

    /// Parses a complete `[ r1 r2 ... ]` array of PDF real or integer
    /// numbers, returning an empty list when `text` is not one.
    internal static func realArray(in text: String) -> [Double] {
      guard let data = text.data(using: .isoLatin1) else { return [] }
      var parser = ValueParser(data)
      parser.skipTrivia()
      guard parser.consume("[") else { return [] }
      var values: [Double] = []
      while true {
        parser.skipTrivia()
        if parser.consume("]") {
          guard (try? parser.requireEnd()) != nil else { return [] }
          return values
        }
        guard
          let token = try? parser.atom(),
          let value = Self.pdfReal(data.subdata(in: token))
        else {
          return []
        }
        values.append(value)
      }
    }

    /// Parses one complete `/Name` token and returns it with `#xx`
    /// escapes decoded and its leading slash retained.
    internal static func decodedName(in text: String) -> String? {
      guard let data = text.data(using: .isoLatin1) else { return nil }
      var parser = ValueParser(data)
      parser.skipTrivia()
      guard
        let parsed = try? parser.name(),
        (try? parser.requireEnd()) != nil
      else {
        return nil
      }
      return "/" + parsed.decoded
    }

    /// Parses either a single `/Name` or an array `[ /Name ... ]` of
    /// decoded filter names without leading slashes.
    internal static func decodedNameList(in text: String) throws -> [String] {
      guard let data = text.data(using: .isoLatin1) else {
        throw PdfSigningError.structureUnreadable
      }
      var parser = ValueParser(data)
      parser.skipTrivia()
      if parser.has("/") {
        let single = try parser.name()
        try parser.requireEnd()
        return [single.decoded]
      }
      guard parser.consume("[") else {
        throw PdfSigningError.structureUnreadable
      }
      var names: [String] = []
      while true {
        parser.skipTrivia()
        if parser.consume("]") {
          try parser.requireEnd()
          return names
        }
        let next = try parser.name()
        names.append(next.decoded)
      }
    }

    /// Parses a PDF numeric token without scientific exponent notation.
    private static func pdfReal(_ data: Data) -> Double? {
      let raw = ValueLexemes.text(data)
      guard
        !raw.isEmpty,
        !raw.contains("e"),
        !raw.contains("E"),
        raw.allSatisfy({ character in
          character.isASCII
            && (character.isNumber
              || character == "+"
              || character == "-"
              || character == ".")
        }),
        let number = Double(raw),
        number.isFinite
      else {
        return nil
      }
      return number
    }
  }
}
