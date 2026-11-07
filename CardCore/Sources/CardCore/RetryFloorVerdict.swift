// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The retry floor's decision for one PIN-bearing operation.
///
/// The cases are closed and exhaustive on purpose: a caller must switch
/// over all of them, and no case converts an unknown reading into
/// permission.
public enum RetryFloorVerdict: Equatable, Sendable {
  /// Three or more attempts remain - or the credential is already
  /// verified in this session, which proves a counter reset to its
  /// maximum (S1 v4.2 §3.5); the operation may proceed. A PUK at no
  /// tries left or blocked proceeds too, to let the card answer.
  case proceed

  /// Zero attempts remain: the PIN is blocked and is reset with the
  /// PUK. The PUK is never refused on this ground when judged for the
  /// credential it presents; the card answers a blocked PUK itself.
  case refuseBlocked

  /// One or two attempts remain: refuse before prompting for or sending
  /// any credential. RefineID never consumes a near-last attempt.
  case refuseLowAttempts

  /// The retry state was missing, malformed, stale, or unreadable: fail
  /// closed without talking to the card.
  case refuseUnreadable
}
