// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The shortest and longest value a credential accepts, in digits.
///
/// The predicate is `1 <= minimum <= maximum`: an empty credential has
/// no meaning and a range whose minimum exceeds its maximum admits
/// nothing.
public struct PasswordLengthRange: Equatable, Hashable, Sendable {
  /// Shortest accepted value, in digits.
  public let minimum: Int

  /// Longest accepted value, in digits.
  public let maximum: Int

  /// The accepted digit counts as a closed range.
  public var digitCounts: ClosedRange<Int> {
    minimum...maximum
  }

  /// A range from `minimum` to `maximum` digits, or nil unless
  /// `1 <= minimum <= maximum`.
  public init?(minimum: Int, maximum: Int) {
    guard minimum >= 1, minimum <= maximum else { return nil }
    self.minimum = minimum
    self.maximum = maximum
  }

  /// Whether a value of `digitCount` digits lies in the range.
  public func contains(_ digitCount: Int) -> Bool {
    digitCounts.contains(digitCount)
  }

  /// The digit counts both ranges accept, or nil when they share none.
  public func intersection(_ other: Self) -> Self? {
    Self(minimum: max(minimum, other.minimum), maximum: min(maximum, other.maximum))
  }
}
