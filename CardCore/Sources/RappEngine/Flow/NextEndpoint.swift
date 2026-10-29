// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The endpoint a requester opens next (RAPP v26.10.29 §4.2, "Trying Each
/// Custodian in Pairing Mode" item 1).
internal enum NextEndpoint<Endpoint: Equatable>: Equatable {
  /// No endpoint is left to open, or the connection limit is reached.
  case exhausted
  /// Only endpoints that answered busy are left, and none of their waits
  /// has passed: ask again at this monotonic time.
  case notBefore(UInt64)
  /// Open a pairing connection to this endpoint now.
  case open(Endpoint)
}
