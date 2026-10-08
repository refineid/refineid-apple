// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One operation-protocol body encoded from the specification's schemas.
internal struct OperationVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case name = "name"
    case messageType = "message_type"
    case bodyHex = "body_hex"
    case requestHashHex = "request_hash_hex"
  }

  internal let name: String
  internal let messageType: String
  internal let bodyHex: String
  /// The commitment a request body hashes to, on request vectors.
  internal let requestHashHex: String?
}
