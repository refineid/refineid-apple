// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The key a pairing routes sessions with (RAPP v26.10.22 §4.3).
internal struct RoutingKey {
  private let secret: SymmetricKey

  internal init?(record: PairRecord) {
    guard let derived = record.pairKey(info: PairKeys.routingInfo) else { return nil }
    secret = derived
  }

  internal init(key: SymmetricKey) {
    secret = key
  }

  /// Finds the pairing a session routing names, checking every key so the
  /// time taken does not depend on which one matches.
  internal static func route(keys: [Self?], profile: String, routing: SessionRouting) -> Int? {
    var found: Int?
    for (index, candidate) in keys.enumerated() {
      let admitted = candidate?.admits(profile: profile, routing: routing) ?? false
      if admitted, found == nil {
        found = index
      }
    }
    return found
  }

  /// `HMAC-SHA-256(K_route, len(domain) || domain || nonce)`, first 16 bytes.
  internal func tag(profile: String, nonce: Data) -> Data? {
    guard let domain = RoutingPreamble.domain(forProfile: profile) else { return nil }
    let domainBytes = Data(domain.utf8)
    let digest = PairKeys.mac(secret, [Data([UInt8(domainBytes.count)]), domainBytes, nonce])
    return Data(digest.prefix(SessionRouting.tagSize))
  }

  internal func admits(profile: String, routing: SessionRouting) -> Bool {
    guard let expected = tag(profile: profile, nonce: routing.nonce) else { return false }
    return PairKeys.constantTimeEqual(expected, routing.tag)
  }
}
