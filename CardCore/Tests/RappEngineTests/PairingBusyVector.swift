// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One `pairing_busy` corpus vector: a busy answer's exact bootstrap bytes.
internal struct PairingBusyVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case encodedHex = "encoded_hex"
    case name = "name"
    case retryAfterMilliseconds = "retry_after_ms"
  }

  internal let name: String
  internal let retryAfterMilliseconds: UInt64
  internal let encodedHex: String
}
