// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// FIFO cancellation-safe mutex used by Swift Testing suite scopes to
/// serialize access to process-wide test-host singletons. Each scope owns
/// an independent instance for its singleton domain.
internal actor SharedSuiteAccess {
  private static let waiterIDStep: UInt64 = 1

  private var occupied = false
  private var nextWaiterID: UInt64 = 0
  private var waiters: [(waiterID: UInt64, continuation: CheckedContinuation<Void, any Error>)] =
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
