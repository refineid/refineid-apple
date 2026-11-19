// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0

import Foundation
import Synchronization
import Testing

/// Buffers callback events and records missing or excess delivery without skipping cleanup.
///
/// One `wait(for:timeout:)` covers the whole awaited group with a single deadline,
/// so the failure path never multiplies its budget by the number of events.
internal final class TestEvent: Sendable {
  private struct Timeout: Error {}

  private static let singleEventCount = 1
  private static let initialEventCount = 0
  private let events: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  private let expectedCount: Int
  private let description: String
  private let signalCount = Mutex(initialEventCount)

  internal convenience init(description: String) {
    self.init(description: description, expectedCount: Self.singleEventCount)
  }

  internal init(description: String, expectedCount: Int) {
    let stream = AsyncStream.makeStream(of: Void.self)
    events = stream.stream
    continuation = stream.continuation
    self.expectedCount = expectedCount
    self.description = description
  }

  /// Waits for every listed event under one shared deadline.
  @discardableResult
  internal static func wait(for events: [TestEvent], timeout: TimeInterval) async -> Bool {
    do {
      try await waitForDelivery(of: events, timeout: timeout)
      return true
    } catch {
      let descriptions = events.map(\.description).joined(separator: ", ")
      Issue.record("Callback wait ended without the expected delivery: \(descriptions).")
      return false
    }
  }

  /// Races one deadline task against the group, so the timeout is spent once
  /// regardless of how many events the caller awaits.
  private static func waitForDelivery(of events: [TestEvent], timeout: TimeInterval) async throws {
    try await withThrowingTaskGroup(of: Void.self) { tasks in
      tasks.addTask {
        for event in events {
          var iterator = event.events.makeAsyncIterator()
          for _ in repeatElement((), count: event.expectedCount) {
            guard await iterator.next() != nil else { throw CancellationError() }
          }
        }
      }
      tasks.addTask {
        try await Task.sleep(for: .seconds(timeout))
        throw Timeout()
      }
      defer { tasks.cancelAll() }
      try await tasks.next()
    }
  }

  internal func signal() {
    let exceeded = signalCount.withLock { count in
      count += Self.singleEventCount
      return count > expectedCount
    }
    if exceeded {
      Issue.record("Callback event delivered more often than expected: \(description).")
    }
    continuation.yield()
  }
}
