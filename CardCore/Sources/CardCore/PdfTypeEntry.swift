// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One dictionary entry of an object's body, read as a value rather
/// than searched for as text.
///
/// A body may hold a string or a stream whose bytes spell `/Type /Page`
/// or `/FT /Sig`. Reading the entry makes what the dictionary says
/// decide, not what the bytes contain (ISO 32000-1 clause 7.3.7).
internal enum PdfTypeEntry {
  /// The dictionary an object body opens with: everything before the
  /// `stream` keyword when it has a stream, the body itself otherwise.
  internal static func dictionary(of body: String) -> String {
    guard let stream = body.range(of: "stream") else { return body }
    return String(body[..<stream.lowerBound])
  }

  /// The trimmed value of the entry `name`, when the body opens with a
  /// dictionary that has it.
  internal static func value(of name: String, in body: String) -> String? {
    guard
      let dictionary = try? PdfValidationStore.DictionarySyntax(dictionary(of: body)),
      let entry = dictionary.entry(named: name)
    else {
      return nil
    }
    return dictionary.value(of: entry).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
