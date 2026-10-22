// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The bound RAPP v26.10.22 §4.2 ("Trying Each Custodian in Pairing Mode"
/// item 5) sets on the tries of one typed code.
internal enum PairingCandidateLimit {
  /// Pairing connections one typed code may open, whether or not CPace runs
  /// on them (`pairing_candidates_max`).
  internal static let connections = 8
}
