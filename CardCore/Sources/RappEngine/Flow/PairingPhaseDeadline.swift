// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The finite post-PAKE deadlines of RAPP v26.10.1 §3.3.7.
///
/// Once CPace hands off, the ceremony is no longer bound by the offer's
/// lifetime but by these monotonic windows.
internal enum PairingPhaseDeadline {
  /// From local CPace handoff to a completed Noise_XXpsk3 handshake.
  internal static let handshakeMilliseconds: UInt64 = 10_000
  /// From local Noise completion to stored trust.
  internal static let confirmationMilliseconds: UInt64 = 10_000

  internal static func after(_ start: UInt64, _ window: UInt64) -> UInt64 {
    let (deadline, overflow) = start.addingReportingOverflow(window)
    return overflow ? UInt64.max : deadline
  }
}
