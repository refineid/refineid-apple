// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How long a requester that quits waits for its `service_withdrawn` closes
/// to leave before it exits (RAPP v26.10.22 §4.5 item 8).
internal enum QuitWithdrawalBound {
  /// The bound, in milliseconds.
  internal static let milliseconds: UInt64 = 1_000
}
