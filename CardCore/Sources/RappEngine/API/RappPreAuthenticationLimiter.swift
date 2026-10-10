// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Admits at most one pre-authentication pairing attempt per 500 ms
/// (RAPP v26.10.9 §3.3.8).
///
/// The custodian asks before it serves the offer to a new connection or
/// takes a candidate Y_A; a refused connection is closed with no state
/// change.
public final class RappPreAuthenticationLimiter: @unchecked Sendable {
  /// The spacing §3.3.8 fixes between admitted attempts.
  public static let minimumSpacingMilliseconds: UInt64 = 500

  private let lock = NSLock()
  private var lastAdmittedMilliseconds: UInt64?

  /// Creates a limiter that has admitted nothing yet.
  public init() {
    // Nothing admitted yet.
  }

  /// Whether an attempt arriving at `nowMonotonicMs` may proceed; an
  /// admitted attempt starts the next spacing window.
  public func admit(nowMonotonicMs: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let last = lastAdmittedMilliseconds,
      nowMonotonicMs < last || nowMonotonicMs - last < Self.minimumSpacingMilliseconds
    {
      return false
    }
    lastAdmittedMilliseconds = nowMonotonicMs
    return true
  }
}
