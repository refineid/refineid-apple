// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// The one rule for keeping PIN 1, stated as a table over every probe answer.
///
/// Both token extension paths and the phone's RAPP path hold a PIN 1 only
/// on this rule.
@Suite
internal struct Pin1RetentionTests {
  @Test
  internal func holdsOnlyAtTheFullAllowance() throws {
    let full = try #require(RetryCount(attemptsRemaining: RetryCount.pristineAllowance))
    #expect(Pin1Retention.permitsHolding(after: .remaining(full)))
    // Any spent attempt, however many remain, drops the held value.
    for remaining in UInt8(0)..<RetryCount.pristineAllowance {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(!Pin1Retention.permitsHolding(after: .remaining(count)))
    }
  }

  @Test
  internal func aVerifiedCardHolds() {
    // A successful VERIFY sets the try counter to its limit (S1 v4.2
    // section 3.5), so the probe's verified answer proves a full counter.
    #expect(Pin1Retention.permitsHolding(after: .verified))
  }

  @Test
  internal func anUnreadableOrLockedCounterNeverHolds() {
    #expect(!Pin1Retention.permitsHolding(after: .locked))
    #expect(!Pin1Retention.permitsHolding(after: .invalidated))
    #expect(!Pin1Retention.permitsHolding(after: .noInformation))
    #expect(!Pin1Retention.permitsHolding(after: .other(0)))
  }
}
