// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A period during which a trust anchor's status was granted, both
/// ends inclusive; open-ended when `end` is nil.
public struct GrantedPeriod: Sendable, Equatable {
  /// The period without bounds: from the earliest instant, open-ended.
  public static let unbounded = Self(start: .distantPast, end: nil)

  /// When the status was granted.
  public let start: Date

  /// When it was withdrawn; nil while it holds.
  public let end: Date?

  private init(start: Date, end: Date?) {
    self.start = start
    self.end = end
  }

  /// The period from `start` until `end`, or open-ended; nil when `end`
  /// precedes `start`.
  public init?(start: Date, until end: Date?) {
    if let end, end < start { return nil }
    self.init(start: start, end: end)
  }

  /// Whether `instant` lies inside the period.
  public func covers(_ instant: Date) -> Bool {
    start <= instant && (end.map { end in instant <= end } ?? true)
  }
}
