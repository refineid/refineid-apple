// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One revocation hint for an instance and an epoch.
internal struct RevocationHintVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case epoch = "epoch"
    case instanceName = "instance_name"
    case name = "name"
    case revocationHintHex = "revocation_hint_hex"
    case unixTimeSeconds = "unix_time_seconds"
  }

  internal let name: String
  internal let instanceName: String
  internal let unixTimeSeconds: UInt64
  internal let epoch: UInt64
  internal let revocationHintHex: String
}
