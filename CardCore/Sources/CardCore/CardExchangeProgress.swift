// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Thread-safe transport timing without retaining command or response payloads.
public final class CardExchangeProgress: @unchecked Sendable {
  private struct Operation {
    let identifier: String
    let instruction: String
    let started: ContinuousClock.Instant
    var submitted: Duration?
    var callback: Duration?
    var waiterTimedOut = false
  }

  private let lock = NSLock()
  private var active: Operation?

  /// Creates an empty timing record for one transport operation.
  public init() {
    active = nil
  }

  /// Starts tracking one command, retaining only its instruction byte.
  public func begin(request: Data) {
    let instructionIndex = 1
    let instruction =
      request.dropFirst(instructionIndex).first
      .map { String(format: "%02X", $0) } ?? "?"
    lock.lock()
    active = Operation(
      identifier: UUID().uuidString, instruction: instruction, started: .now)
    lock.unlock()
  }

  /// Records when the asynchronous transport API returns to its caller.
  public func submitted() {
    lock.lock()
    if let started = active?.started {
      active?.submitted = started.duration(to: .now)
    }
    lock.unlock()
  }

  /// Records callback entry and returns whether the waiter already timed out.
  public func completed() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let started = active?.started {
      active?.callback = started.duration(to: .now)
    }
    return active?.waiterTimedOut ?? false
  }

  /// Records that the response waiter exhausted its budget.
  public func timedOut() {
    lock.lock()
    active?.waiterTimedOut = true
    lock.unlock()
  }

  /// A snapshot correlating field loss, submission, and callback timing.
  public func snapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    guard let active else { return "operation=none" }
    let submitted = active.submitted.map(TraceTiming.milliseconds) ?? "pending"
    let callback = active.callback.map(TraceTiming.milliseconds) ?? "pending"
    let elapsed = TraceTiming.milliseconds(active.started.duration(to: .now))
    return "operation=\(active.identifier) ins=\(active.instruction) elapsedMs=\(elapsed) "
      + "submitReturnMs=\(submitted) callbackMs=\(callback) waiterTimedOut=\(active.waiterTimedOut)"
  }
}
