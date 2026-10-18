// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The key a pairing's revocation hints are made with (RAPP v26.10.18 §4.6).
///
/// Derived whether or not the pairing's storage was confirmed: an
/// unconfirmed record is exactly what gets revoked.
internal struct RevocationKey {
  private let secret: SymmetricKey

  /// The raw key, for the retention that outlives the pairing's record.
  internal var bytes: Data {
    secret.withUnsafeBytes { Data($0) }
  }

  internal init?(record: PairRecord) {
    guard let derived = record.revocableKey(info: PairKeys.revocationInfo) else { return nil }
    secret = derived
  }

  internal init(key: SymmetricKey) {
    secret = key
  }

  /// `HMAC-SHA-256(K_rev, len || instance || epoch_be64)`, first 8 bytes.
  internal func hint(instance: InstanceName, epoch: UInt64) -> Data {
    let digest = PairKeys.mac(
      secret, [Data([UInt8(instance.bytes.count)]), instance.bytes, PairKeys.bigEndian(epoch)])
    return Data(digest.prefix(AnnouncementText.hintSize))
  }

  /// Whether `record` announces this pairing's revocation.
  ///
  /// The `revoked` entries, published on `instance`, are checked for the
  /// hint of `epoch` and either neighbour without stopping at a match. A
  /// record without `revoked` matches nothing.
  internal func matches(
    _ record: DiscoveryRecord, instance: InstanceName, epoch: UInt64
  ) -> Bool {
    guard let revoked = record.revoked else { return false }
    var matched = false
    for candidate in DiscoveryKey.window(epoch) {
      let expected = hint(instance: instance, epoch: candidate)
      for entry in revoked.entries {
        matched = PairKeys.constantTimeEqual(expected, entry) || matched
      }
    }
    return matched
  }
}
