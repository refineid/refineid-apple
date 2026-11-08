// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How long a requester redials after a loss of the session, or after the first failed dial since
/// the custodian last appeared (RAPP v26.11.8 §8.3, `redial_window_ms`).
///
/// It equals the identity offer's grace, so the requester stops redialing when it would stop
/// offering the custodian's identity after a loss.
internal enum RedialWindow {
  /// The window, in milliseconds.
  internal static let milliseconds: UInt64 = IdentityOfferGrace.milliseconds
}
