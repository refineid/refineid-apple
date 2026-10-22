// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The key a pairing's discovery hints are made with (RAPP v26.10.22 §4.3).
internal struct DiscoveryKey {
  private let secret: SymmetricKey

  internal init?(record: PairRecord) {
    guard let derived = record.pairKey(info: PairKeys.discoveryInfo) else { return nil }
    secret = derived
  }

  internal init(key: SymmetricKey) {
    secret = key
  }

  /// `value` and its neighbours, without wrapping.
  internal static func window(_ value: UInt64) -> [UInt64] {
    [value == 0 ? nil : value - 1, value, value == .max ? nil : value + 1].compactMap(\.self)
  }

  /// `HMAC-SHA-256(K_disc, epoch_be64)`, first 8 bytes.
  internal func hint(epoch: UInt64) -> Data {
    Data(PairKeys.mac(secret, [PairKeys.bigEndian(epoch)]).prefix(AnnouncementText.hintSize))
  }

  /// Whether any hint in `record` is this pairing's for `epoch` or either
  /// neighbour, checked without stopping at a match.
  internal func matches(_ record: DiscoveryRecord, epoch: UInt64) -> Bool {
    let expected = Self.window(epoch).map { hint(epoch: $0) }
    var matched = false
    for published in record.hints {
      for candidate in expected {
        matched = PairKeys.constantTimeEqual(candidate, published) || matched
      }
    }
    return matched
  }
}
