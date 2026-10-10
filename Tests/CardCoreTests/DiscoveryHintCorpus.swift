// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `discovery_hint` section of the RAPP v26.10.9 conformance corpus.
internal struct DiscoveryHintCorpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case discoveryHint = "discovery_hint"
  }

  internal let discoveryHint: [DiscoveryHintCorpusVector]
}
