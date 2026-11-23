// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0

#if DEBUG && os(macOS)
  import Testing

  @Suite
  internal struct DssGateFixtureScopeCancellationTests {
    private static let singleQueuedWaiter = 1
    private static let twoQueuedWaiters = 2
    private static let raceIterations = 50
    private static let zeroQueuedWaiters = 0

    private static func waitUntilQueued(
      _ access: DssGateFixtureScope.Access,
      expectedCount: Int
    ) async {
      while await access.queuedWaiterCount < expectedCount {
        await Task.yield()
      }
    }

    @Test
    internal func cancellingQueuedAcquirerDoesNotWedgeSubsequentAcquirers() async throws {
      let access = DssGateFixtureScope.Access()
      try await access.acquire()

      let queued = Task {
        try await access.acquire()
      }
      await Self.waitUntilQueued(access, expectedCount: Self.singleQueuedWaiter)

      queued.cancel()
      await #expect(throws: CancellationError.self) {
        try await queued.value
      }

      await access.release()
      try await access.acquire()
      await access.release()
    }

    @Test
    internal func cancellingFirstQueuedWaiterStillHandsOwnershipToNextLiveWaiter() async throws {
      let access = DssGateFixtureScope.Access()
      try await access.acquire()

      let firstWaiter = Task {
        try await access.acquire()
      }
      await Self.waitUntilQueued(access, expectedCount: Self.singleQueuedWaiter)

      let secondWaiter = Task {
        try await access.acquire()
        await access.release()
      }
      await Self.waitUntilQueued(access, expectedCount: Self.twoQueuedWaiters)

      firstWaiter.cancel()
      await #expect(throws: CancellationError.self) {
        try await firstWaiter.value
      }

      await access.release()
      try await secondWaiter.value
    }

    @Test
    internal func preCancelledTaskThrowsWithoutAcquiringLock() async throws {
      let access = DssGateFixtureScope.Access()
      let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        try await access.acquire()
      }
      await #expect(throws: CancellationError.self) {
        try await task.value
      }

      try await access.acquire()
      await access.release()
    }

    @Test
    internal func cancellingAndReleasingConcurrentlyNeverLeaksLock() async throws {
      let access = DssGateFixtureScope.Access()
      for _ in Self.zeroQueuedWaiters..<Self.raceIterations {
        try await access.acquire()

        let racingWaiter = Task {
          try await access.acquire()
          await access.release()
        }
        await Self.waitUntilQueued(access, expectedCount: Self.singleQueuedWaiter)

        racingWaiter.cancel()
        await access.release()
        _ = await racingWaiter.result

        try await access.acquire()
        await access.release()
      }
      let remaining = await access.queuedWaiterCount
      #expect(remaining == Self.zeroQueuedWaiters)
    }
  }
#endif
