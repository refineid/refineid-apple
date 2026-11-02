// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// How a PACE mechanism maps the card nonce to the session generator
/// (ICAO Doc 9303 Part 11 section 4.4.3.3).
public enum PaceMapping: Equatable, Sendable {
  /// Generic mapping, `G' = s * G + H` (section 4.4.3.3.1): the one the
  /// handshake runs.
  case generic

  /// Integrated mapping (section 4.4.3.3.2): listed by the organization
  /// cards, recognised and not run.
  case integrated
}
