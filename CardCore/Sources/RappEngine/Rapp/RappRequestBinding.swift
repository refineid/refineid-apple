// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Everything one typed request binds itself to when it is hashed.
///
/// The commitment is session-independent: it names the pairing, so a
/// retransmission across sessions hashes the same (RAPP v26.10.9 §8.2.1).
internal struct RappRequestBinding {
  internal let pairIdentifier: Data
  internal let operationIdentifier: Data
  internal let profile: String
  internal let action: String
  internal let context: [String: WireValue]
  internal let payload: [String: WireValue]
}
