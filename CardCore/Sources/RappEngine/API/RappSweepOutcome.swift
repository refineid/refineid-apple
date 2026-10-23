// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What an idle-expiry sweep did with one pairing (RAPP v26.10.22 §4.6 item
/// 5).
public enum RappSweepOutcome: Equatable, Sendable {
  /// The pairing went 30 days without an established session: it is stored
  /// as forgotten and keeps its key only for the close (§4.6 items 2 to 4).
  /// Withdraw its identity; send nothing and tell no user.
  case expired
  /// Nothing changed: no session is established and the pairing is short of
  /// the idle limit, or the record is forgotten already.
  case kept
  /// A session to the pairing is established: its time is recorded and
  /// stored, and the pairing stays.
  case recorded

  internal init(_ outcome: PairRecordSweepOutcome) {
    switch outcome {
    case .recorded:
      self = .recorded

    case .kept:
      self = .kept

    case .expired:
      self = .expired
    }
  }
}
