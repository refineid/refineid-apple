// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One dictionary entry of an object's body, read as a value rather
/// than searched for as text.
///
/// A body may hold a string or a stream whose bytes spell `/Type /Page`
/// or `/FT /Sig`, or spell `stream` inside a string literal or comment.
/// Parsing the leading dictionary makes what the dictionary says decide,
/// not what arbitrary bytes contain (ISO 32000-1 clause 7.3.7).
internal enum PdfTypeEntry {
  /// Whether `body` opens with a dictionary followed by the `stream`
  /// keyword.
  internal static func hasStream(_ body: String) -> Bool {
    PdfValidationStore.DictionarySyntax.leading(in: body)?.hasStream == true
  }

  /// The leading dictionary of `body`, when it opens with one.
  internal static func dictionarySyntax(
    of body: String
  ) -> PdfValidationStore.DictionarySyntax? {
    PdfValidationStore.DictionarySyntax.leading(in: body)?.syntax
  }

  /// The value of `name` in the leading dictionary of `body`: decoded
  /// when the value is a single `/Name` token, or trimmed as written
  /// otherwise.
  internal static func value(of name: String, in body: String) -> String? {
    guard
      let dictionary = Self.dictionarySyntax(of: body),
      let entry = dictionary.entry(named: name)
    else {
      return nil
    }
    let raw = dictionary.value(of: entry)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let decoded = PdfValidationStore.TypedValues.decodedName(in: raw) {
      return decoded
    }
    return raw
  }
}
