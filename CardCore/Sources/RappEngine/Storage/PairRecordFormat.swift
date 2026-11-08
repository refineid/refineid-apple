// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A pair record's format version: the RAPP version that last changed the
/// record's layout, `[Year, Month, Day]` as the wire version is written.
///
/// A stored record carrying any other value is refused and dropped;
/// nothing converts it.
internal struct PairRecordFormat: Equatable, Sendable {
  /// The year of RAPP v26.11.8, which set the current layout.
  private static let layoutYear: UInt64 = 26
  /// Its month.
  private static let layoutMonth: UInt64 = 11
  /// Its day.
  private static let layoutDay: UInt64 = 2

  /// The format every record is stored in and read back from.
  internal static let current = Self(year: layoutYear, month: layoutMonth, day: layoutDay)

  internal let year: UInt64
  internal let month: UInt64
  internal let day: UInt64

  /// The stored form, `[year, month, day]`.
  internal var value: WireValue {
    .array([.unsigned(year), .unsigned(month), .unsigned(day)])
  }
}
