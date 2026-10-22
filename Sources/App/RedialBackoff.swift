// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How long a requester waits before it dials its phone again after a
/// session that ended or a dial that brought none up.
///
/// The first wait is short, for a phone that was only briefly out of reach;
/// each further failure doubles it up to a bound, so a phone that keeps
/// refusing or not answering is not dialled in a tight loop. A session that
/// confirms the card starts it over.
internal struct RedialBackoff: Equatable, Sendable {
  // MARK: Static Properties

  private static let firstDelaySeconds: Int64 = 2
  private static let longestDelaySeconds: Int64 = 32
  private static let growth: Int64 = 2

  private static let firstDelay: Duration = .seconds(firstDelaySeconds)

  /// The longest wait between two dials.
  internal static let longestDelay: Duration = .seconds(longestDelaySeconds)

  // MARK: Properties

  /// Sessions ended or dials failed since the last start over.
  internal private(set) var failures = 0

  // MARK: Static Functions

  /// The wait after `failures` consecutive failures; none before the first.
  internal static func delay(afterFailures failures: Int) -> Duration {
    guard failures > 0 else { return .zero }
    var delay = firstDelay
    for _ in 1..<failures {
      delay *= Self.growth
      if delay >= longestDelay { return longestDelay }
    }
    return delay
  }

  // MARK: Functions

  /// Records one more failure and answers the wait it calls for.
  internal mutating func recordFailure() -> Duration {
    failures += 1
    return Self.delay(afterFailures: failures)
  }

  /// Starts over, so the next failure waits the first delay.
  internal mutating func reset() {
    failures = 0
  }
}
