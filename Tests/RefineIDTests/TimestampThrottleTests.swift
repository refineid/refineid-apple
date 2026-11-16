// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import OSLog
import Testing

@testable import RefineIDTestHost

/// Verifies per-document fair-use spacing across timestamp exchanges.
@Suite
internal struct TimestampThrottleTests {
  /// Monotonic test clock recording requested sleeps without wall-clock delay.
  internal final class FakeClock: Sendable {
    private let origin: ContinuousClock.Instant
    private let storage = OSAllocatedUnfairLock(
      initialState: (elapsed: Duration.zero, sleeps: [Duration]())
    )

    internal var sleeps: [Duration] {
      storage.withLock { $0.sleeps }
    }

    internal init(origin: ContinuousClock.Instant) {
      self.origin = origin
    }

    internal func now() -> ContinuousClock.Instant {
      storage.withLock { origin.advanced(by: $0.elapsed) }
    }

    internal func advance(by delta: Duration) {
      storage.withLock { $0.elapsed += delta }
    }

    internal func sleep(_ duration: Duration) {
      storage.withLock { current in
        current.sleeps.append(duration)
        current.elapsed += duration
      }
    }
  }

  /// Synthetic failure thrown by a simulated authority refusal.
  private enum SimulatedError: Error, Equatable {
    case tooManyRequests
  }

  private static let expectedSpacingSeconds = 15
  private static let negativeOriginOffsetSeconds = -500
  private static let intraDocumentEvidenceSeconds = 2
  private static let interDocumentUserDelaySeconds = 6
  private static let remainingAfterUserDelaySeconds = 9
  private static let idleGapAboveSpacingSeconds = 20
  private static let spuriousWakeFirstSliceSeconds = 4
  private static let spuriousWakeSecondSliceSeconds = 5
  private static let spuriousWakeRemainingSeconds = 6
  private static let cancelledWaitElapsedSeconds = 3
  private static let remainingAfterCancelledWaitSeconds = 12
  private static let firstAttemptIndex = 1
  private static let tokenAnswer = "token"

  /// The shipped spacing matches the 15-second authority fair-use policy.
  @Test
  internal func shippedSpacingIsFifteenSeconds() {
    #expect(TimestampThrottle.minimumDocumentSpacingSeconds == Self.expectedSpacingSeconds)
    #expect(
      TimestampThrottle.minimumDocumentSpacing == .seconds(Self.expectedSpacingSeconds)
    )
  }

  /// Follow-up timestamps on one document run immediately while extending the
  /// 15-second horizon for the next document, including across negative clock offsets.
  @Test
  internal func sameDocumentFollowUpSkipsWaitAndExtendsHorizonForNextDocument() async throws {
    let clock = FakeClock(
      origin: ContinuousClock.now.advanced(by: .seconds(Self.negativeOriginOffsetSeconds))
    )
    let throttle = TimestampThrottle(
      now: clock.now,
      sleep: { duration in clock.sleep(duration) },
      spacing: TimestampThrottle.minimumDocumentSpacing
    )

    let firstDocument = throttle.makeDocumentSession()
    _ = try await firstDocument.perform { Self.tokenAnswer }
    clock.advance(by: .seconds(Self.intraDocumentEvidenceSeconds))
    _ = try await firstDocument.perform { Self.tokenAnswer }
    #expect(clock.sleeps.isEmpty)

    let secondDocument = throttle.makeDocumentSession()
    _ = try await secondDocument.perform { Self.tokenAnswer }
    _ = try await secondDocument.perform { Self.tokenAnswer }
    #expect(clock.sleeps == [TimestampThrottle.minimumDocumentSpacing])

    clock.advance(by: .seconds(Self.interDocumentUserDelaySeconds))
    let thirdDocument = throttle.makeDocumentSession()
    _ = try await thirdDocument.perform { Self.tokenAnswer }
    #expect(
      clock.sleeps == [
        TimestampThrottle.minimumDocumentSpacing,
        .seconds(Self.remainingAfterUserDelaySeconds),
      ]
    )
  }

  /// No wait is added when at least 15 seconds already passed since the previous document.
  @Test
  internal func elapsedDelayAboveMinimumNeedsNoSleep() async throws {
    let clock = FakeClock(origin: ContinuousClock.now)
    let throttle = TimestampThrottle(
      now: clock.now,
      sleep: { duration in clock.sleep(duration) },
      spacing: TimestampThrottle.minimumDocumentSpacing
    )

    _ = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }
    clock.advance(by: .seconds(Self.idleGapAboveSpacingSeconds))
    _ = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }

    #expect(clock.sleeps.isEmpty)
  }

  /// Early sleep wakeups re-check the monotonic clock until the full horizon arrives.
  @Test
  internal func spuriousEarlyWakeupsLoopUntilTargetInstant() async throws {
    let clock = FakeClock(origin: ContinuousClock.now)
    let wakeCounter = OSAllocatedUnfairLock(initialState: 0)
    let throttle = TimestampThrottle(
      now: clock.now,
      sleep: { requested in
        let wakeIndex = wakeCounter.withLock { count -> Int in
          count += 1
          return count
        }
        switch wakeIndex {
        case Self.firstAttemptIndex:
          clock.sleep(.seconds(Self.spuriousWakeFirstSliceSeconds))

        case Self.firstAttemptIndex + Self.firstAttemptIndex:
          clock.sleep(.seconds(Self.spuriousWakeSecondSliceSeconds))

        default:
          clock.sleep(requested)
        }
      },
      spacing: TimestampThrottle.minimumDocumentSpacing
    )

    _ = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }
    _ = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }

    #expect(
      clock.sleeps == [
        .seconds(Self.spuriousWakeFirstSliceSeconds),
        .seconds(Self.spuriousWakeSecondSliceSeconds),
        .seconds(Self.spuriousWakeRemainingSeconds),
      ]
    )
  }

  /// A failed exchange does not unlock immediate follow-up; its retry waits 15 seconds.
  @Test
  internal func failedExchangeRequiresFullSpacingBeforeRetry() async throws {
    let clock = FakeClock(origin: ContinuousClock.now)
    let attempts = OSAllocatedUnfairLock(initialState: 0)
    let throttle = TimestampThrottle(
      now: clock.now,
      sleep: { duration in clock.sleep(duration) },
      spacing: TimestampThrottle.minimumDocumentSpacing
    )

    let flakyDocument = throttle.makeDocumentSession()
    await #expect(throws: SimulatedError.tooManyRequests) {
      _ = try await flakyDocument.perform {
        let attempt = attempts.withLock { count -> Int in
          count += 1
          return count
        }
        if attempt == Self.firstAttemptIndex {
          throw SimulatedError.tooManyRequests
        }
        return Self.tokenAnswer
      }
    }
    #expect(clock.sleeps.isEmpty)

    let recovered = try await flakyDocument.perform { Self.tokenAnswer }
    #expect(recovered == Self.tokenAnswer)
    #expect(clock.sleeps == [TimestampThrottle.minimumDocumentSpacing])

    _ = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }
    #expect(
      clock.sleeps == [
        TimestampThrottle.minimumDocumentSpacing,
        TimestampThrottle.minimumDocumentSpacing,
      ]
    )
  }

  /// Concurrent tasks reserve distinct 15-second slots without blocking on in-flight HTTP.
  @Test
  internal func concurrentDocumentsReserveDistinctSlotsOutsideInFlightExchange() async throws {
    let clock = FakeClock(origin: ContinuousClock.now)
    let throttle = TimestampThrottle(
      now: clock.now,
      sleep: { duration in clock.sleep(duration) },
      spacing: TimestampThrottle.minimumDocumentSpacing
    )
    let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()
    let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()

    let firstTask = Task {
      try await throttle.makeDocumentSession().perform { () -> String in
        enteredContinuation.yield()
        var iterator = releaseStream.makeAsyncIterator()
        _ = await iterator.next()
        return Self.tokenAnswer
      }
    }

    var enteredIterator = enteredStream.makeAsyncIterator()
    _ = await enteredIterator.next()

    let secondAnswer = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }
    #expect(secondAnswer == Self.tokenAnswer)
    #expect(clock.sleeps == [TimestampThrottle.minimumDocumentSpacing])

    releaseContinuation.yield()
    releaseContinuation.finish()
    let firstAnswer = try await firstTask.value
    #expect(firstAnswer == Self.tokenAnswer)
  }

  /// Cancelling a task during its spacing wait skips the exchange and releases its tail slot.
  @Test
  internal func cancellationDuringWaitSkipsAuthorityAndRollsBackSlot() async throws {
    let clock = FakeClock(origin: ContinuousClock.now)
    let secondExchangeCalled = OSAllocatedUnfairLock(initialState: false)
    let sleepAttempt = OSAllocatedUnfairLock(initialState: 0)
    let throttle = TimestampThrottle(
      now: clock.now,
      sleep: { duration in
        let attempt = sleepAttempt.withLock { count -> Int in
          count += 1
          return count
        }
        if attempt == Self.firstAttemptIndex {
          clock.advance(by: .seconds(Self.cancelledWaitElapsedSeconds))
          throw CancellationError()
        }
        clock.sleep(duration)
      },
      spacing: TimestampThrottle.minimumDocumentSpacing
    )

    _ = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }

    await #expect(throws: CancellationError.self) {
      _ = try await throttle.makeDocumentSession().perform { () -> String in
        secondExchangeCalled.withLock { $0 = true }
        return Self.tokenAnswer
      }
    }
    #expect(!secondExchangeCalled.withLock { $0 })

    _ = try await throttle.makeDocumentSession().perform { Self.tokenAnswer }
    #expect(clock.sleeps == [.seconds(Self.remainingAfterCancelledWaitSeconds)])
  }
}
