// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How long an endpoint that sent a close waits for the peer's echo: a
/// requester that quits or turns remote use off with a session open, and a
/// custodian withdrawing each session (RAPP v26.11.2 §4.5 items 1 and 8,
/// §7.1 item 7).
internal enum QuitWithdrawalBound {
  /// The bound, in milliseconds.
  internal static let milliseconds: UInt64 = 1_000
}
