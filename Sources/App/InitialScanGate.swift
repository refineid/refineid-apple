// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Holds what waits for the first live look at the card readers, and
/// releases each waiter once: when the look is taken, or once its bound has
/// passed without it, whichever comes first.
///
/// A reader that never answers then delays no waiter past its bound.
@MainActor
internal final class InitialScanGate {
  /// Whether the first look was taken.
  internal private(set) var isComplete = false

  private var waiters: [UUID: @MainActor () -> Void] = [:]

  /// The first look was taken: every waiter runs now.
  internal func complete() {
    guard !isComplete else { return }
    isComplete = true
    let released = waiters
    waiters = [:]
    for waiter in released.values {
      waiter()
    }
  }

  /// Runs `action` once the first look was taken, at once when it was, or
  /// after `limit` without it.
  internal func wait(atMost limit: Duration, _ action: @escaping @MainActor () -> Void) {
    guard !isComplete else {
      action()
      return
    }
    let identifier = UUID()
    waiters[identifier] = action
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: limit)
      self?.release(identifier)
    }
  }

  private func release(_ identifier: UUID) {
    waiters.removeValue(forKey: identifier)?()
  }
}
