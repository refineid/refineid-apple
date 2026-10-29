// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored withdrawal corpus (RAPP v26.10.29 §4.5).

internal struct WithdrawalHintVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case counter = "counter"
    case instanceName = "instance_name"
    case name = "name"
    case unixTimeSeconds = "unix_time_seconds"
    case withdrawalHintHex = "withdrawal_hint_hex"
  }

  internal let name: String
  internal let instanceName: String
  internal let unixTimeSeconds: UInt64
  internal let counter: UInt64
  internal let withdrawalHintHex: String
}
