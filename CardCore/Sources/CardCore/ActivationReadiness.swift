// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Whether activation may proceed, decided before any credential is
/// spent.
public enum ActivationReadiness: Equatable, Sendable {
  /// The card shows evidence of prior activation; running activation
  /// again would burn a retry against a credential the holder already
  /// replaced.
  case alreadyActivated

  /// The PIN awaits activation; the flow may proceed.
  case ready

  /// The card gives no evidence either way, so no activation is
  /// offered.
  case undecided
}
