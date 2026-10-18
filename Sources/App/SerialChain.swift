// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Runs bodies one after another in the order they arrive, and lets a
/// body that calls back into the chain proceed instead of waiting for
/// itself.
///
/// A card session holder puts every use of its channel through one
/// chain, so two operations, or a preparation and an operation, never
/// touch the channel at once. A call made from inside a running body
/// (a session failure closing the holder, the holder yielding to the
/// app's own card work it triggered) is re-entrant and runs at once:
/// queuing it behind the body it came from would wait forever.
internal actor SerialChain {
  /// Whether the current task runs inside a chained body.
  @TaskLocal private static var insideBody = false

  /// The last body queued; the next one runs after it.
  private var tail: Task<Void, Never>?

  /// Runs `body` after every body queued before it, or at once when the
  /// caller is itself a chained body.
  internal func run<Value: Sendable>(
    _ body: @escaping @Sendable () async -> Value
  ) async -> Value {
    if Self.insideBody {
      return await body()
    }
    let previous = tail
    let task = Task { () -> Value in
      await previous?.value
      return await Self.$insideBody.withValue(true) {
        await body()
      }
    }
    tail = Task { _ = await task.value }
    return await task.value
  }
}
