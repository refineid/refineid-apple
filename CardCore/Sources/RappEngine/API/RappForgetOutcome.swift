// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What forgetting a pairing did (RAPP v26.10.21 §4.6).
public enum RappForgetOutcome: Equatable, Sendable {
  /// The pairing was never confirmed; its key is destroyed and nobody is
  /// told.
  case destroyed
  /// The record is marked forgotten and keeps its key until the next
  /// session delivers the `pairing_revoked` close, or for 30 days: dial or
  /// route as usual, then deliver the close in place of `session.ready`.
  case noticePending
}
