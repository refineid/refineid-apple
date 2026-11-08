// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The verification screens' text and dates.
internal enum VerifyText {
  /// One string of the document-signing table.
  internal static func text(
    _ key: StaticString,
    _ fallback: String.LocalizationValue
  ) -> String {
    String(localized: key, defaultValue: fallback, table: "DocumentSigning")
  }

  /// A verified time as the screens show it.
  internal static func formatted(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
