// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The time left on a pairing lockout, in the words the custodian shows.
///
/// The remaining time derives from the instant the lockout lifts, so a
/// view that redraws every ``tick`` counts down without keeping a counter.
internal enum PairingLockCountdown {
  /// How often a shown lockout redraws.
  internal static let tick: TimeInterval = 1
  /// From this many seconds on the time reads as minutes and seconds.
  internal static let secondsPerMinute = 60

  /// Whole seconds left at `now`, rounded up; zero once the lockout lifted.
  internal static func remainingSeconds(until: Date, at now: Date) -> Int {
    Int(max(0, until.timeIntervalSince(now)).rounded(.up))
  }

  /// What the user is told at `now`: seconds under a minute, m:ss above.
  internal static func message(until: Date, at now: Date) -> String {
    let seconds = remainingSeconds(until: until, at: now)
    guard seconds >= secondsPerMinute else {
      return String(localized: "Pairing locked. Try again in \(seconds) s.")
    }
    let clock = Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    return String(localized: "Pairing locked. Try again in \(clock).")
  }
}
