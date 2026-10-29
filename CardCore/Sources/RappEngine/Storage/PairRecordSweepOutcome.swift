// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What an idle-expiry sweep did with one pairing (RAPP v26.10.29 §4.6 item
/// 5).
internal enum PairRecordSweepOutcome: Equatable, Sendable {
  /// The pairing had no established session for
  /// ``PairRecord/pairingIdleExpiryDays``: the record is forgotten at the
  /// sweep's time and keeps its key only for the close (§4.6 items 2 to 4).
  /// Nothing is sent and no user is told.
  case expired
  /// Nothing changed: no session is established and the pairing is short
  /// of the idle limit, or the record is not active.
  case kept
  /// A session to the pairing is established: the sweep recorded its time
  /// and the pairing stays.
  case recorded
}
