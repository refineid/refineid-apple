// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The verification screens' text and dates.
internal enum VerifyText {
  /// The style of `formattedDay`, in the app's locale.
  internal static let dayStyle = Date.FormatStyle(
    date: .abbreviated, time: .omitted, timeZone: .gmt)

  /// One string of the document-signing table.
  internal static func text(
    _ key: StaticString,
    _ fallback: String.LocalizationValue
  ) -> String {
    String(localized: key, defaultValue: fallback, table: "DocumentSigning")
  }

  /// A day as the screens show it, without the time: the validity of
  /// an archive timestamp, read in UTC, where the certificates and the
  /// suitability table state it.
  internal static func formattedDay(_ date: Date) -> String {
    date.formatted(Self.dayStyle)
  }

  /// A verified time as the screens show it.
  internal static func formatted(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
