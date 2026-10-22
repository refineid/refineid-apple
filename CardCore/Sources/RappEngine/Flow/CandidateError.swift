// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A ledger call the tries of one typed code do not admit.
internal enum CandidateError: Error, Equatable, Sendable {
  /// A pairing connection is open; it closes before the next one opens.
  case connectionOpen
  /// No pairing connection is open, or CPace already runs on it.
  case noConnection
  /// No CPace runs on the open connection.
  case noTry
  /// CPace already ran on this offer with the code: the same custodian,
  /// found on another transport. Close the connection without CPace.
  case offerAlreadyTried
  /// A custodian accepted the code, or every one tried refused it.
  case settled
}
