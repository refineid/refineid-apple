// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Outcome of a counter-safe retry probe, after the reference
/// implementation's classification.
///
/// Both probe forms are explicitly side-effect-free:
/// no retry or usage counter changes.
public enum RetryProbeOutcome: Equatable, Sendable {
  /// `6984`: the referenced credential data is invalidated.
  case invalidated

  /// `6983`: the credential is blocked. A blocked PIN is reset with
  /// the PUK; under S4-1 §4.6.1 a factory PIN is blocked until
  /// activation.
  case locked

  /// The card answered without a usable counter (`6300`, or an
  /// attributes object without one).
  case noInformation

  /// Any other status word, preserved for diagnostics.
  case other(UInt16)

  /// The counter: this many attempts remain.
  case remaining(RetryCount)

  /// `9000`: the credential is already verified in this session; the
  /// card reports no counter.
  case verified
}
