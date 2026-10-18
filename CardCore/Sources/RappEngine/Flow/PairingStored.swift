// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One peer's word that its pairing record is durably stored, naming the
/// pairing it stored (RAPP v26.10.18 §7.1).
internal struct PairingStored: Equatable {
  internal var pairIdentifier: Data

  internal static func from(body: [String: WireValue]) throws -> Self {
    var fields = body
    guard case .bytes(let identifier)? = fields.removeValue(forKey: "pair_id"),
      identifier.count == PairRecordSize.pairIdentifier
    else {
      throw MessageFieldError.invalidField("pair_id")
    }
    guard fields.isEmpty else { throw MessageFieldError.invalidField("body") }
    return Self(pairIdentifier: identifier)
  }

  internal func body() -> [String: WireValue] {
    ["pair_id": .bytes(pairIdentifier)]
  }
}
