// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0

#if os(macOS)
  import Testing

  /// Serializes suites that change shared test-host fixtures.
  internal struct DssGateFixtureScope: SuiteTrait, TestScoping {
    internal actor Access {
      private static let waiterIDStep: UInt64 = 1

      private var occupied = false
      private var nextWaiterID: UInt64 = 0
      private var waiters:
        [(waiterID: UInt64, continuation: CheckedContinuation<Void, any Error>)] =
          []

      internal var queuedWaiterCount: Int {
        waiters.count
      }

      internal func acquire() async throws {
        try Task.checkCancellation()
        if !occupied {
          occupied = true
          return
        }
        nextWaiterID &+= Self.waiterIDStep
        let waiterID = nextWaiterID
        try await withTaskCancellationHandler {
          try await self.waitForTurn(waiterID: waiterID)
        } onCancel: {
          Task { await self.cancelWaiter(waiterID: waiterID) }
        }
        if Task.isCancelled {
          release()
          throw CancellationError()
        }
      }

      private func waitForTurn(waiterID: UInt64) async throws {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
          } else if !occupied {
            occupied = true
            continuation.resume()
          } else {
            waiters.append((waiterID: waiterID, continuation: continuation))
          }
        }
      }

      internal func release() {
        if waiters.isEmpty {
          occupied = false
        } else {
          waiters.removeFirst().continuation.resume()
        }
      }

      private func cancelWaiter(waiterID: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.waiterID == waiterID }) else {
          return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
      }
    }

    @TaskLocal internal static var hasOwnership = false
    private static let access = Access()

    internal var isRecursive: Bool { false }

    internal func scopeProvider(for test: Test, testCase _: Test.Case?) -> Self? {
      test.isSuite ? self : nil
    }

    internal func provideScope(
      for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
      try await Self.access.acquire()
      do {
        try await Self.$hasOwnership.withValue(true) {
          try await function()
        }
        await Self.access.release()
      } catch {
        await Self.access.release()
        throw error
      }
    }
  }
#endif
