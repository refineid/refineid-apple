// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's exponential backoff after pairing lockouts
/// (RAPP v26.10.9 §3.3.7).
///
/// After n consecutive locked-out offers a new offer waits min(2^n, 300)
/// seconds. The count lives in memory only: it resets on a successful
/// pairing, after fifteen minutes without a lockout, and when the process
/// ends.
public final class RappPairingBackoff: @unchecked Sendable {
  /// The one counter a process keeps.
  public static let shared = RappPairingBackoff()

  private static let ceilingSeconds: UInt64 = 300
  private static let saturatingExponent: UInt64 = 9
  private static let inactivityResetSeconds: TimeInterval = 900
  private static let backoffBase: UInt64 = 2

  private let lock = NSLock()
  private var consecutiveLockouts: UInt64 = 0
  private var lastLockout: Date?

  /// Creates a counter with no lockouts recorded.
  public init() {
    // Starts with no lockouts recorded.
  }

  /// Records one offer destroyed by three failed attempts.
  public func recordLockout(at now: Date = Date()) {
    lock.lock()
    defer { lock.unlock() }
    expireIfInactive(now: now)
    consecutiveLockouts = min(consecutiveLockouts + 1, Self.saturatingExponent)
    lastLockout = now
  }

  /// Clears the count after a pairing completed.
  public func recordSuccess() {
    lock.lock()
    defer { lock.unlock() }
    consecutiveLockouts = 0
    lastLockout = nil
  }

  /// Seconds before a new offer may be shown; zero when one may be shown now.
  public func secondsUntilNextOffer(at now: Date = Date()) -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    expireIfInactive(now: now)
    guard consecutiveLockouts > 0, let lastLockout else { return 0 }
    var delay: UInt64 = 1
    for _ in 0..<consecutiveLockouts {
      delay *= Self.backoffBase
    }
    delay = min(delay, Self.ceilingSeconds)
    let elapsed = UInt64(max(0, now.timeIntervalSince(lastLockout)))
    return elapsed >= delay ? 0 : delay - elapsed
  }

  private func expireIfInactive(now: Date) {
    guard let lastLockout,
      now.timeIntervalSince(lastLockout) >= Self.inactivityResetSeconds
    else { return }
    consecutiveLockouts = 0
    self.lastLockout = nil
  }
}
