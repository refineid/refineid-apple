// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Admits at most one pre-authentication pairing attempt per 500 ms
/// (RAPP v26.10.29 §3.3 item 6).
///
/// The custodian reads the routing preamble of every accepted connection,
/// then asks. When it refuses, a session connection is closed unanswered,
/// and a pairing connection, while an offer is live, is answered with
/// ``RappPairingBridge/busyBytes(nowMonotonicMs:spacingWaitMs:)`` carrying
/// ``waitMs(nowMonotonicMs:)`` at that time, in place of
/// ``RappPairingBridge/bootstrapBytes(nowMonotonicMs:)``, and then closed
/// (§4.2, "Busy Refusal"). Nothing else changes.
public final class RappPreAuthenticationLimiter: @unchecked Sendable {
  /// The spacing §3.3 item 6 fixes between admitted attempts.
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

  /// Milliseconds from `nowMonotonicMs` until ``admit(nowMonotonicMs:)``
  /// would admit an attempt.
  ///
  /// Zero when it would admit one now. Asking moves nothing.
  public func waitMs(nowMonotonicMs: UInt64) -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    guard let last = lastAdmittedMilliseconds else { return 0 }
    let elapsed = nowMonotonicMs > last ? nowMonotonicMs - last : 0
    return elapsed < Self.minimumSpacingMilliseconds
      ? Self.minimumSpacingMilliseconds - elapsed : 0
  }
}
