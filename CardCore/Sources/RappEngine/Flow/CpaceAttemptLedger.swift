// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's attempt accounting for one offer (RAPP v26.10.9 §3.3).
///
/// An attempt is admitted before Y_B and T_B leave the custodian, so a peer
/// that tests T_B and disconnects still spends it. A successful T_A consumes
/// the offer; three failed attempts destroy it.
internal struct CpaceAttemptLedger {
  internal static let maximumAttempts = 3
  /// Non-extendable window from admission to a verified T_A.
  internal static let attemptWindowMilliseconds: UInt64 = 5_000

  internal private(set) var admitted = 0
  internal private(set) var failed = 0
  internal private(set) var consumed = false
  private var activeDeadline: UInt64?

  internal var isExhausted: Bool { failed >= Self.maximumAttempts }
  internal var hasActiveAttempt: Bool { activeDeadline != nil }

  /// Whether another attempt may still be admitted under this offer.
  internal var acceptsAnotherAttempt: Bool {
    !consumed && !isExhausted && admitted < Self.maximumAttempts
  }

  /// Reserves one attempt, clamped to the offer deadline.
  internal mutating func admit(nowMilliseconds: UInt64, offerExpiresAt: UInt64) -> Bool {
    guard !consumed, activeDeadline == nil, admitted < Self.maximumAttempts,
      nowMilliseconds < offerExpiresAt
    else { return false }
    let (window, overflow) = nowMilliseconds.addingReportingOverflow(
      Self.attemptWindowMilliseconds)
    admitted += 1
    activeDeadline = min(overflow ? UInt64.max : window, offerExpiresAt)
    return true
  }

  /// Whether the active attempt may still complete.
  internal func attemptIsLive(nowMilliseconds: UInt64) -> Bool {
    guard let activeDeadline else { return false }
    return nowMilliseconds < activeDeadline
  }

  /// Ends the active attempt as failed; disconnects and timeouts are not refunded.
  internal mutating func failActiveAttempt() {
    guard activeDeadline != nil else { return }
    activeDeadline = nil
    failed += 1
  }

  /// Ends the active attempt as the one that consumed the offer.
  internal mutating func consume() {
    activeDeadline = nil
    consumed = true
  }
}
