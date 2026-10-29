// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The TXT conventions the session and withdrawn records share (RAPP
/// v26.10.29 §4.5 and the transport hierarchy §4.3).
///
/// Keys match without regard to ASCII case (RFC 6763 §6.4) and appear at
/// most once; values match exactly, and hint lists are lowercase hex.
internal enum AnnouncementText {
  /// A record with an unknown or repeated key.
  internal struct Malformed: Error {}

  internal static let hintSize = 8
  internal static let versionKey = "v"
  internal static let version = "1"
  internal static let modeKey = "mode"

  private static let separator: Character = ","
  private static let hexDigits = Array("0123456789abcdef")
  private static let digitsPerByte = 2
  private static let nibbleBits: UInt8 = 4
  private static let lowNibble: UInt8 = 0b1111
  private static let asciiCaseOffset =
    Unicode.Scalar(UInt8(ascii: "a")).value - Unicode.Scalar(UInt8(ascii: "A")).value

  /// The hints of the `limit` most recently used pairings, ties ordered by
  /// hint bytes.
  internal static func mostRecentlyUsed(_ candidates: [AnnouncementCandidate], limit: Int)
    -> [Data]
  {
    candidates.sorted { left, right in
      if left.lastUsedMilliseconds != right.lastUsedMilliseconds {
        return left.lastUsedMilliseconds > right.lastUsedMilliseconds
      }
      return left.hint.lexicographicallyPrecedes(right.hint)
    }
    .prefix(limit)
    .map(\.hint)
  }

  /// The values of `keys` in `entries`, in the order of `keys`.
  ///
  /// - Throws: ``Malformed`` when a key is unknown or repeated in any case.
  internal static func values(_ entries: [(String, String)], keys: [String]) throws -> [String?] {
    var values = [String?](repeating: nil, count: keys.count)
    for (key, value) in entries {
      guard let index = keys.firstIndex(where: { asciiLowercased($0) == asciiLowercased(key) }),
        values[index] == nil
      else { throw Malformed() }
      values[index] = value
    }
    return values
  }

  /// A comma-separated list of lowercase-hex entries.
  internal static func encode(_ hints: [Data]) -> String {
    hints.map { hint in
      String(hint.flatMap { [hexDigits[Int($0 >> nibbleBits)], hexDigits[Int($0 & lowNibble)]] })
    }
    .joined(separator: String(separator))
  }

  /// The hints of a comma-separated list of lowercase-hex entries; empty
  /// when any entry is malformed or there are more than `maximum`.
  internal static func decode(_ list: String, maximum: Int) -> [Data] {
    var hints: [Data] = []
    for entry in list.split(separator: separator, omittingEmptySubsequences: false) {
      guard let hint = decodeEntry(entry) else { return [] }
      hints.append(hint)
    }
    return hints.count <= maximum ? hints : []
  }

  private static func asciiLowercased(_ text: String) -> String {
    String(
      String.UnicodeScalarView(
        text.unicodeScalars.map { scalar in
          ("A"..."Z").contains(scalar)
            ? Unicode.Scalar(scalar.value + asciiCaseOffset) ?? scalar : scalar
        }))
  }

  private static func decodeEntry(_ text: Substring) -> Data? {
    let digits = Array(text)
    guard digits.count == hintSize * digitsPerByte else { return nil }
    var hint = Data(capacity: hintSize)
    var index = 0
    while index < digits.count {
      guard let high = hexDigits.firstIndex(of: digits[index]),
        let low = hexDigits.firstIndex(of: digits[index + 1])
      else { return nil }
      hint.append(UInt8(high) << nibbleBits | UInt8(low))
      index += digitsPerByte
    }
    return hint
  }
}
