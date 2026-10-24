// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// A stamped line from the card holder, for reading a run back in order.
///
/// The holder's events reach two observers on different queues, so the
/// order two lines appear in says nothing about the order they happened.
/// A stamp does, and it is the only way to tell an answer that arrived
/// too late from one that arrived too early.
///
/// The same rule as ``AppTrace``: Debug and Profile only. TestFlight and
/// Release define no `DEBUG`, so the call compiles to nothing and the
/// `@autoclosure` line is never built.
internal enum HolderTrace {
  // MARK: Static Properties

  #if DEBUG
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-holder")
    private static let started = Date()
  #endif

  // MARK: Static Functions

  /// Writes one line, stamped with the seconds since the process began.
  internal static func say(_ line: @autoclosure () -> String) {
    #if DEBUG
      let elapsed = Date().timeIntervalSince(started)
      let formatted = String(format: "[stream-holder %7.3f] %@", elapsed, line())
      print(formatted)
      fflush(stdout)
      logger.notice("\(formatted, privacy: .private)")
      AppTrace.append(formatted)
    #endif
  }
}
