// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The display-name vectors of the conformance corpus (RAPP v26.11.8 §4.3
/// items 3 and 4, §7.1): `pairing.hello`, `session.ready` and
/// `session.hello` envelopes with names that are accepted or refused.
internal struct DisplayNameCorpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case pairingHello = "pairing_hello"
    case sessionName = "session_name"
  }

  internal let pairingHello: [DisplayNameVector]
  internal let sessionName: [DisplayNameVector]
}
