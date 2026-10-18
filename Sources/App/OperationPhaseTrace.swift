// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Stamps the phases of one remote card operation into the shared trace,
/// in milliseconds since the request arrived, so the diagnostics report
/// shows where the time went.
///
/// Phones serve one operation at a time, so one clock suffices. Debug
/// and Profile only: a shipped build compiles both calls to nothing.
internal enum OperationPhaseTrace {
  #if DEBUG
    private static let lock = NSLock()
    nonisolated(unsafe) private static var started: ContinuousClock.Instant?

    /// A request arrived; later marks count from here.
    internal static func begin() {
      lock.lock()
      started = ContinuousClock.now
      lock.unlock()
      HolderTrace.say("phase request-received ms=0.0")
    }

    /// One phase of the current operation ended.
    internal static func mark(_ phase: StaticString) {
      lock.lock()
      let origin = started
      lock.unlock()
      guard let origin else { return }
      let elapsed = TraceTiming.milliseconds(origin.duration(to: ContinuousClock.now))
      HolderTrace.say("phase \(phase) ms=\(elapsed)")
    }
  #else
    internal static func begin() {
      // A shipped build keeps no trace.
    }

    internal static func mark(_: StaticString) {
      // A shipped build keeps no trace.
    }
  #endif
}
