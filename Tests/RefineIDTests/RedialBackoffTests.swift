// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// The wait before a requester dials its phone again doubles from a short
/// first wait to a bound, and starts over on a session that came up.
@Suite
internal struct RedialBackoffTests {
  /// Enough consecutive failures for the wait to reach its bound.
  internal static let failuresPastTheBound = 8

  /// The doubling the back-off applies.
  private static let growth = 2

  @Test("No failure, no wait; then each failure doubles the wait to the bound")
  internal func doublesToTheBound() {
    #expect(RedialBackoff.delay(afterFailures: 0) == .zero)
    let first = RedialBackoff.delay(afterFailures: 1)
    #expect(first > .zero)
    var expected = first
    for failures in 1...Self.failuresPastTheBound {
      #expect(RedialBackoff.delay(afterFailures: failures) == expected)
      expected = min(expected * Self.growth, RedialBackoff.longestDelay)
    }
    #expect(
      RedialBackoff.delay(afterFailures: Self.failuresPastTheBound) == RedialBackoff.longestDelay)
  }

  @Test("Recorded failures grow the wait; a reset starts it over")
  internal func recordAndReset() {
    var backoff = RedialBackoff()
    let first = backoff.recordFailure()
    let second = backoff.recordFailure()
    #expect(second == first * Self.growth)
    backoff.reset()
    #expect(backoff.failures == 0)
    let afresh = backoff.recordFailure()
    #expect(afresh == first)
  }
}
