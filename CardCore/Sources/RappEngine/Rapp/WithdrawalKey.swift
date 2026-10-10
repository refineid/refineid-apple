// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The key a pairing's withdrawal hints are made with (RAPP v26.10.10
/// §4.5).
internal struct WithdrawalKey {
  private let secret: SymmetricKey

  internal init?(record: PairRecord) {
    guard let derived = record.pairKey(info: PairKeys.withdrawalInfo) else { return nil }
    secret = derived
  }

  internal init(key: SymmetricKey) {
    secret = key
  }

  /// `HMAC-SHA-256(K_wd, len || instance || counter_be64)`, first 8 bytes.
  internal func hint(instance: InstanceName, counter: UInt64) -> Data {
    let digest = PairKeys.mac(
      secret, [Data([UInt8(instance.bytes.count)]), instance.bytes, PairKeys.bigEndian(counter)])
    return Data(digest.prefix(AnnouncementText.hintSize))
  }

  /// Whether `record` carries this pairing's hint for `instance` at
  /// `counter` or either neighbour, checked without stopping at a match.
  internal func matches(_ record: WithdrawnRecord, instance: InstanceName, counter: UInt64)
    -> Bool
  {
    var matched = false
    for candidate in DiscoveryKey.window(counter) {
      let expected = hint(instance: instance, counter: candidate)
      for entry in record.entries {
        matched = PairKeys.constantTimeEqual(expected, entry) || matched
      }
    }
    return matched
  }
}
