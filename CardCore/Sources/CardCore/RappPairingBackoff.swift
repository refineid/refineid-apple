// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's exponential backoff after pairing lockouts
/// (RAPP v26.10.22 §3.3 item 7).
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

  /// The instant a new offer may be shown; nil when one may be shown now.
  public func nextOfferDate(at now: Date = Date()) -> Date? {
    lock.lock()
    defer { lock.unlock() }
    expireIfInactive(now: now)
    guard consecutiveLockouts > 0, let lastLockout else { return nil }
    var delay: UInt64 = 1
    for _ in 0..<consecutiveLockouts {
      delay *= Self.backoffBase
    }
    let liftsAt = lastLockout.addingTimeInterval(TimeInterval(min(delay, Self.ceilingSeconds)))
    return liftsAt > now ? liftsAt : nil
  }

  private func expireIfInactive(now: Date) {
    guard let lastLockout,
      now.timeIntervalSince(lastLockout) >= Self.inactivityResetSeconds
    else { return }
    consecutiveLockouts = 0
    self.lastLockout = nil
  }
}
