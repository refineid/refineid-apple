// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How long a requester keeps a pairing its user forgot with no session
/// open, for its one attempt to deliver the `pairing_revoked` close (RAPP
/// v26.11.2 §4.6 item 6, `revocation_attempt_bound_ms`).
internal enum RevocationAttemptBound {
  /// The bound, in milliseconds.
  internal static let milliseconds: UInt64 = 10_000
}
