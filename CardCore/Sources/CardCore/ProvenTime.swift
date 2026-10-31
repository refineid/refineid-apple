// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A time an anchored timestamp proves; made only from
/// `TimestampState.anchored`, so a claimed time cannot become one.
public struct ProvenTime: Sendable, Equatable, Comparable {
  /// The proven instant.
  public let date: Date

  /// The time of one anchored timestamp.
  internal init(_ date: Date) {
    self.date = date
  }

  /// Whether `lhs` is earlier than `rhs`.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.date < rhs.date
  }
}
