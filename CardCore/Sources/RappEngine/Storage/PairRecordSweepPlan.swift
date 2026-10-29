// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The times a sweep leaves in one record and what it did, decided before
/// anything changes so that the store commits first (RAPP v26.10.29 §4.6
/// item 5).
internal struct PairRecordSweepPlan: Equatable, Sendable {
  internal let outcome: PairRecordSweepOutcome
  internal let lastSessionAtMilliseconds: UInt64?
  internal let forgottenAtMilliseconds: UInt64?
}
