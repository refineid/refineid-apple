// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Where a custodian sends a connection after its first frame.
public enum RappRoute: Equatable, Sendable {
  /// The pairing ceremony.
  case pairing
  /// Nothing: close without answering and change no stored state.
  case refuse
  /// A session of the stored pairing at this index of the records given.
  case session(index: Int)
}
