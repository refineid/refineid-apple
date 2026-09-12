// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite
internal struct RetryFloorTests {
  @Test
  internal func unreadableFailsClosed() {
    #expect(RetryFloor.evaluate(freshReading: nil) == .refuseUnreadable)
  }

  @Test
  internal func zeroCanProceedWithoutSpendingAnAttempt() throws {
    let reading = try #require(RetryCount(attemptsRemaining: 0))
    #expect(RetryFloor.evaluate(freshReading: reading) == .proceed)
  }

  @Test
  internal func everyCountBelowFloorRefusesWithoutBlocking() throws {
    for value in 1..<RetryFloor.minimumAttemptsToProceed {
      let reading = try #require(RetryCount(attemptsRemaining: value))
      #expect(RetryFloor.evaluate(freshReading: reading) == .refuseLowAttempts)
    }
  }

  @Test
  internal func everyCountAtOrAboveFloorProceeds() throws {
    for value in RetryFloor.minimumAttemptsToProceed...RetryCount.maximumPlausible {
      let reading = try #require(RetryCount(attemptsRemaining: value))
      #expect(RetryFloor.evaluate(freshReading: reading) == .proceed)
    }
  }

  @Test
  internal func floorIsAboveTheLastTwoAttempts() {
    // The invariant behind the numbers: the floor must keep at least two
    // attempts out of reach so RefineID can never consume the last one.
    #expect(RetryFloor.minimumAttemptsToProceed >= 3)
  }

  @Test
  internal func probeOutcomeUsesOnlyThatCredential() throws {
    let safe = try #require(
      RetryCount(attemptsRemaining: RetryFloor.minimumAttemptsToProceed))
    #expect(RetryFloor.evaluate(probeOutcome: .remaining(safe)) == .proceed)
    #expect(RetryFloor.evaluate(probeOutcome: .locked) == .proceed)
    #expect(RetryFloor.evaluate(probeOutcome: .noInformation) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .other(0x6A88)) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .verified) == .proceed)
  }
}
