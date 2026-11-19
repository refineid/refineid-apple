// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0

import Foundation
import Testing

internal struct TestEventTests {
  private static let expectedEvents = 2
  private static let eventDeadline: TimeInterval = 1
  private static let missingDeadline: TimeInterval = 0.01

  @Test
  internal func bufferedEventsRemainAvailableUntilTheWaitStarts() async {
    let event = TestEvent(description: "buffered events", expectedCount: Self.expectedEvents)
    event.signal()
    event.signal()
    #expect(await TestEvent.wait(for: [event], timeout: Self.eventDeadline))
  }

  @Test
  internal func missingEventsRecordFailureAndReturnForCleanup() async {
    let event = TestEvent(description: "missing event")
    var delivered = true
    await withKnownIssue("The missing event must record a failure.") {
      delivered = await TestEvent.wait(for: [event], timeout: Self.missingDeadline)
    }
    #expect(!delivered)
  }

  @Test
  internal func cancellationRecordsFailureAndReturnsForCleanup() async {
    let event = TestEvent(description: "cancelled event")
    var delivered = true
    await withKnownIssue("The cancelled wait must record a failure.") {
      let waiting = Task {
        await TestEvent.wait(for: [event], timeout: Self.eventDeadline)
      }
      waiting.cancel()
      delivered = await waiting.value
    }
    #expect(!delivered)
  }

  @Test
  internal func excessEventsRecordFailureAfterTheWaitReturns() async {
    let event = TestEvent(description: "single event")
    event.signal()
    #expect(await TestEvent.wait(for: [event], timeout: Self.eventDeadline))
    withKnownIssue("An additional callback must record a failure.") {
      event.signal()
    }
  }
}
