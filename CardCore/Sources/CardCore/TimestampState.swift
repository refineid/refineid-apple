// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What one time-stamp token was found to be (EN 319 102-1 clause 5.4).
public enum TimestampState: Sendable, Equatable {
  /// The token verifies, imprints what it time-stamps, and its
  /// authority chains to a time-stamping anchor; it proves its time.
  case anchored(Date)

  /// The token verifies and imprints what it time-stamps under an
  /// authority that is not anchored; the date is only claimed, and the
  /// token proves nothing.
  case claimed(Date)

  /// The token parses but does not verify or does not imprint what it
  /// time-stamps, or its range does not end a revision; it proves
  /// nothing.
  case invalid

  /// The token does not parse, or names a hash this verifier does not
  /// know; it is not judged and proves nothing.
  case unsupported

  /// The time the token proves, when it is anchored.
  public var provenTime: ProvenTime? {
    guard case .anchored(let time) = self else { return nil }
    return ProvenTime(time)
  }

  /// The time the token claims, when it verified but is not anchored.
  public var claimedTime: Date? {
    guard case .claimed(let time) = self else { return nil }
    return time
  }
}
