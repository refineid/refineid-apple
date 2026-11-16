// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Token-aware scanning over PDF byte streams (ISO 32000-1 §7.2, §7.3).
extension PdfBytes {
  /// Whether `position` sits at a PDF token boundary: outside the file,
  /// on whitespace, or on a delimiter octet.
  internal func isTokenBoundary(at position: Int) -> Bool {
    guard position >= 0, position < count else { return true }
    let value = byte(at: position)
    return PdfValues.whitespaceBytes.contains(value)
      || PdfValues.delimiterBytes.contains(value)
  }

  /// Whether `keyword` sits at `position` as a complete PDF token rather
  /// than as part of a longer identifier or `/Name`.
  internal func hasKeywordToken(_ keyword: String, at position: Int) -> Bool {
    guard hasKeyword(keyword, at: position) else { return false }
    if position > 0, byte(at: position - 1) == UInt8(ascii: "/") {
      return false
    }
    return isTokenBoundary(at: position - 1)
      && isTokenBoundary(at: position + keyword.utf8.count)
  }

  /// The first position at or after `from` past whitespace and `%`
  /// comments.
  internal func skippingTrivia(from: Int) -> Int {
    var cursor = max(0, from)
    while cursor < count {
      if PdfValues.whitespaceBytes.contains(byte(at: cursor)) {
        cursor += 1
        continue
      }
      guard byte(at: cursor) == UInt8(ascii: "%") else { return cursor }
      cursor = skippingComment(from: cursor)
    }
    return cursor
  }

  /// Verifies an indirect object header at `offset` and returns the
  /// position right after `obj`.
  internal func objectHeaderEnd(
    at offset: Int,
    expectedNumber: Int?,
    expectedGeneration: Int?
  ) -> Int? {
    let start = skippingWhitespace(from: offset)
    guard
      isTokenBoundary(at: start - 1),
      let number = decimalToken(at: start),
      isTokenBoundary(at: number.end)
    else {
      return nil
    }
    if let expectedNumber, number.value != expectedNumber { return nil }
    let generationAt = skippingWhitespace(from: number.end)
    guard
      let generation = decimalToken(at: generationAt),
      isTokenBoundary(at: generation.end)
    else {
      return nil
    }
    if let expectedGeneration, generation.value != expectedGeneration {
      return nil
    }
    let keywordAt = skippingWhitespace(from: generation.end)
    guard hasKeywordToken(PdfValues.objectKeyword, at: keywordAt) else {
      return nil
    }
    return keywordAt + PdfValues.objectKeyword.utf8.count
  }

  /// The balanced `<< >>` dictionary starting after trivia at `offset`,
  /// skipping comments and string literals inside it.
  internal func balancedDictionary(
    from offset: Int
  ) -> (text: String, end: Int)? {
    let start = skippingTrivia(from: offset)
    guard hasKeyword("<<", at: start) else { return nil }
    var depth = 0
    var cursor = start
    while cursor < count {
      if byte(at: cursor) == UInt8(ascii: "%") {
        cursor = skippingComment(from: cursor)
      } else if byte(at: cursor) == UInt8(ascii: "(") {
        guard let pastString = skippingLiteralString(from: cursor) else {
          return nil
        }
        cursor = pastString
      } else if hasKeyword("<<", at: cursor) {
        depth += 1
        cursor += PdfValues.dictionaryMarkerLength
      } else if hasKeyword(">>", at: cursor) {
        depth -= 1
        cursor += PdfValues.dictionaryMarkerLength
        if depth == 0 {
          return (text(in: start..<cursor), cursor)
        }
      } else if byte(at: cursor) == UInt8(ascii: "<") {
        guard let pastHex = skippingHexString(from: cursor) else { return nil }
        cursor = pastHex
      } else {
        cursor += 1
      }
    }
    return nil
  }

  /// The first occurrence of `keyword` as a standalone token at or after
  /// `from`, skipping comments and string literals.
  internal func keywordTokenRange(
    of keyword: String,
    from: Int
  ) -> Range<Int>? {
    let width = keyword.utf8.count
    guard width > 0, count >= width else { return nil }
    var cursor = max(0, from)
    while cursor + width <= count {
      if byte(at: cursor) == UInt8(ascii: "%") {
        cursor = skippingComment(from: cursor)
      } else if byte(at: cursor) == UInt8(ascii: "(") {
        guard let pastString = skippingLiteralString(from: cursor) else {
          return nil
        }
        cursor = pastString
      } else if !hasKeyword("<<", at: cursor),
        byte(at: cursor) == UInt8(ascii: "<")
      {
        guard let pastHex = skippingHexString(from: cursor) else { return nil }
        cursor = pastHex
      } else if byte(at: cursor) == UInt8(ascii: "/") {
        cursor = skippingName(from: cursor)
      } else if hasKeywordToken(keyword, at: cursor) {
        return cursor..<(cursor + width)
      } else {
        cursor += 1
      }
    }
    return nil
  }

  /// Advances from `%` to the line ending that terminates the comment.
  private func skippingComment(from start: Int) -> Int {
    var cursor = start
    while cursor < count,
      byte(at: cursor) != PdfValues.lineFeedByte,
      byte(at: cursor) != PdfValues.carriageReturnByte
    {
      cursor += 1
    }
    return cursor
  }

  /// Advances past a balanced `(...)` literal string, honouring `\`
  /// escapes.
  private func skippingLiteralString(from start: Int) -> Int? {
    var cursor = start + 1
    var depth = 1
    while cursor < count {
      let current = byte(at: cursor)
      cursor += 1
      if current == UInt8(ascii: "\\") {
        if cursor < count { cursor += 1 }
      } else if current == UInt8(ascii: "(") {
        depth += 1
      } else if current == UInt8(ascii: ")") {
        depth -= 1
        if depth == 0 { return cursor }
      }
    }
    return nil
  }

  /// Advances past a `<...>` hexadecimal string.
  private func skippingHexString(from start: Int) -> Int? {
    var cursor = start + 1
    while cursor < count {
      let current = byte(at: cursor)
      cursor += 1
      if current == UInt8(ascii: ">") { return cursor }
    }
    return nil
  }

  /// Advances past a `/Name` token up to its terminating boundary.
  private func skippingName(from start: Int) -> Int {
    var cursor = start + 1
    while cursor < count, !isTokenBoundary(at: cursor) {
      cursor += 1
    }
    return cursor
  }
}
