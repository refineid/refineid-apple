// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The indirect references an array value carries, in the order written.
internal enum PdfObjectReferences {
  /// The `N G R` references in `value`, as `"N G"`.
  ///
  /// Anything else in the array - a name, a number, a string, a nested
  /// array - is not a reference and is left out, so a caller comparing
  /// two arrays sees the objects they name.
  internal static func references(in value: String) -> [String] {
    let tokens = value.split(whereSeparator: \.isWhitespace)
    var found: [String] = []
    var index = tokens.startIndex
    while index < tokens.endIndex {
      let number = tokens[index]
      let generation = tokens.index(after: index)
      let marker = generation < tokens.endIndex ? tokens.index(after: generation) : generation
      guard
        number.allSatisfy(\.isNumber),
        generation < tokens.endIndex,
        tokens[generation].allSatisfy(\.isNumber),
        marker < tokens.endIndex,
        tokens[marker] == "R"
      else {
        index = generation
        continue
      }
      found.append("\(number) \(tokens[generation])")
      index = tokens.index(after: marker)
    }
    return found
  }
}
