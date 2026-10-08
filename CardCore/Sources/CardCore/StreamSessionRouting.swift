// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which pairing a dial on the session listener is for.
///
/// A dialer's first frame is the session preamble built from its pairing's
/// rendezvous token (discovery hierarchy §4.3). One that names no active
/// pairing is refused: the connection closes and stored state is untouched.
public enum StreamSessionRouting {
  /// The candidate whose preamble `frame` is, or nil for an unknown token.
  public static func route<Candidate>(
    _ frame: Data, among candidates: [Candidate], preamble: (Candidate) -> Data
  ) -> Candidate? {
    candidates.first { preamble($0) == frame }
  }
}
