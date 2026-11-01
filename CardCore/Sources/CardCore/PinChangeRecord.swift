// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What the PIN container says about the PIN having been changed since
/// manufacture (the DF 2F object, S1 v4.2 §3.15.3).
public enum PinChangeRecord: Equatable, Sendable {
  /// Changed at least once: activation has happened.
  case changed

  /// Never changed: the factory state under either scheme.
  case unchanged

  /// Absent or carrying an unknown flag value; no decision may rest
  /// on it.
  case unreadable
}
