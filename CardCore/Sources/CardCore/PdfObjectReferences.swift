// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The indirect references an array value carries, in the order written.
internal enum PdfObjectReferences {
  /// The result of parsing a strict reference-only PDF array.
  internal struct ParsedReferences {
    /// Whether `value` was either empty or a valid `[ N G R ... ]` array.
    internal let isValid: Bool

    /// The parsed indirect references, in written order.
    internal let references: [PdfValidationStore.StoreReference]
  }

  /// Parses `value` as a reference-only array (treating an empty string
  /// as an absent empty list).
  internal static func strictReferences(in value: String) -> ParsedReferences {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ParsedReferences(isValid: true, references: [])
    }
    guard
      let parsed = try? PdfValidationStore.ValueParser.referenceArray(
        in: trimmed
      )
    else {
      return ParsedReferences(isValid: false, references: [])
    }
    return ParsedReferences(isValid: true, references: parsed)
  }

  /// The `N G R` references in `value`, as `"N G"`, when `value` is
  /// empty or a valid reference array.
  internal static func references(in value: String) -> [String] {
    let parsed = Self.strictReferences(in: value)
    guard parsed.isValid else { return [] }
    return parsed.references.map { reference in
      "\(reference.number) \(reference.generation)"
    }
  }
}
