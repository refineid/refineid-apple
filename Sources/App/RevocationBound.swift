// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import RappEngine

/// How long a requester keeps a pairing its user forgot with no session
/// open, for its one attempt to tell the phone (RAPP v26.11.2 §4.6 item 6).
internal enum RevocationBound {
  /// The bound of the attempt.
  internal static let attempt = Duration.milliseconds(Int64(rappRevocationAttemptBoundMs()))
}
