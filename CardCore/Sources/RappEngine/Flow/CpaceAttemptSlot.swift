// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's one attempt slot for an offer (RAPP v26.10.29 §3.3
/// items 1 to 5).
///
/// An attempt is admitted before Y_B and T_B leave the custodian, so a peer
/// that tests T_B and disconnects holds the slot no longer than a completed
/// wrong guess does. A failed attempt frees the slot and changes nothing
/// else; a verified T_A consumes the offer.
internal struct CpaceAttemptSlot {
  /// Non-extendable window from admission to a verified T_A.
  internal static let attemptWindowMilliseconds: UInt64 = 5_000

  private var consumed = false
  private var activeDeadline: UInt64?

  /// Whether another attempt may be admitted under this offer now.
  internal var acceptsAnotherAttempt: Bool { !consumed && activeDeadline == nil }

  /// Admits one attempt whose deadline is clamped to the offer deadline.
  internal mutating func admit(nowMilliseconds: UInt64, offerExpiresAt: UInt64) -> Bool {
    guard acceptsAnotherAttempt, nowMilliseconds < offerExpiresAt else { return false }
    let (window, overflow) = nowMilliseconds.addingReportingOverflow(
      Self.attemptWindowMilliseconds)
    activeDeadline = min(overflow ? UInt64.max : window, offerExpiresAt)
    return true
  }

  /// Whether the active attempt may still complete.
  internal func attemptIsLive(nowMilliseconds: UInt64) -> Bool {
    guard let activeDeadline else { return false }
    return nowMilliseconds < activeDeadline
  }

  /// Ends the active attempt as failed: a disconnect, a timeout or a wrong
  /// T_A frees the slot and leaves the offer as it was.
  internal mutating func endActiveAttempt() {
    activeDeadline = nil
  }

  /// Ends the active attempt as the one that consumed the offer.
  internal mutating func consume() {
    activeDeadline = nil
    consumed = true
  }
}
