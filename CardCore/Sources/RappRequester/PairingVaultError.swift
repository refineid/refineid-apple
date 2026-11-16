// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What a ``PairingVault`` refuses with.
///
/// The forgetting treats them differently: a record that cannot be read is
/// destroyed, one that is gone is left alone, and anything else is tried
/// again by the next attempt.
public enum PairingVaultError: Error, Equatable, Sendable {
  /// The vault holds a record it cannot read.
  case malformed

  /// The vault holds no such pairing.
  case notFound

  /// The vault could not be read or written for another reason.
  case unavailable
}
