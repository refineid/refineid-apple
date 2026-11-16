// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A PDF's bytes, addressed the way the format addresses them.
///
/// A cross-reference table names byte offsets, so every position here
/// is a byte position. This type exists so that no part of the signing
/// path can accidentally reach for a String index: on a document with
/// CRLF line endings `\r\n` is one Swift Character and two bytes, and
/// an offset counted in characters would be short by the number of
/// line endings before it.
internal struct PdfBytes {
  /// The bytes themselves.
  private let bytes: [UInt8]

  /// How many bytes the document has.
  internal var count: Int {
    bytes.count
  }

  /// Wraps a document.
  internal init(_ document: Data) {
    self.bytes = [UInt8](document)
  }

  /// The byte at `position`.
  internal func byte(at position: Int) -> UInt8 {
    bytes[position]
  }

  /// Whether the document opens with `prefix`.
  internal func starts(with prefix: String) -> Bool {
    bytes.starts(with: Array(prefix.utf8))
  }

  /// Whether `keyword` sits exactly at `position`.
  internal func hasKeyword(_ keyword: String, at position: Int) -> Bool {
    let needle = Array(keyword.utf8)
    guard position >= 0, position + needle.count <= bytes.count else {
      return false
    }
    return bytes[position..<(position + needle.count)].elementsEqual(needle)
  }

  /// The first occurrence of `keyword` at or after `from`.
  internal func firstRange(of keyword: String, from: Int) -> Range<Int>? {
    let needle = Array(keyword.utf8)
    guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
    var index = max(0, from)
    while index + needle.count <= bytes.count {
      if bytes[index..<(index + needle.count)].elementsEqual(needle) {
        return index..<(index + needle.count)
      }
      index += 1
    }
    return nil
  }

  /// The last occurrence of `keyword`.
  internal func lastRange(of keyword: String) -> Range<Int>? {
    let needle = Array(keyword.utf8)
    guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
    var index = bytes.count - needle.count
    while index >= 0 {
      if bytes[index..<(index + needle.count)].elementsEqual(needle) {
        return index..<(index + needle.count)
      }
      index -= 1
    }
    return nil
  }

  /// The first position at or after `from` that is not whitespace.
  internal func skippingWhitespace(from: Int) -> Int {
    var cursor = max(0, from)
    while cursor < bytes.count,
      PdfValues.whitespaceBytes.contains(bytes[cursor])
    {
      cursor += 1
    }
    return cursor
  }

  /// The decimal number starting at `position`, or nil when there is
  /// no digit there.
  internal func decimal(at position: Int) -> Int? {
    decimalToken(at: position)?.value
  }

  /// The decimal number starting at `position` and the position just
  /// past its digits, or nil when there is no digit there or it
  /// overflows `Int`.
  internal func decimalToken(at position: Int) -> (value: Int, end: Int)? {
    var cursor = position
    var value = 0
    var sawDigit = false
    while cursor < bytes.count,
      bytes[cursor] >= UInt8(ascii: "0"),
      bytes[cursor] <= UInt8(ascii: "9")
    {
      let digit = Int(bytes[cursor] - UInt8(ascii: "0"))
      let (multiplied, multipliedOverflow) = value.multipliedReportingOverflow(
        by: PdfValues.decimalRadix
      )
      let (added, addedOverflow) = multiplied.addingReportingOverflow(digit)
      guard !multipliedOverflow, !addedOverflow else { return nil }
      value = added
      cursor += 1
      sawDigit = true
    }
    guard sawDigit else { return nil }
    return (value, cursor)
  }

  /// A range of bytes as text.
  ///
  /// Latin-1 keeps one byte to one scalar, which matters when a
  /// dictionary carries a binary /ID string.
  internal func text(in range: Range<Int>) -> String {
    let clamped = range.clamped(to: 0..<bytes.count)
    return String(bytes: bytes[clamped], encoding: .isoLatin1) ?? ""
  }

  /// A range of bytes as raw data, for stream payloads that must not
  /// pass through any text encoding.
  internal func data(in range: Range<Int>) -> Data {
    let clamped = range.clamped(to: 0..<bytes.count)
    return Data(bytes[clamped])
  }
}
