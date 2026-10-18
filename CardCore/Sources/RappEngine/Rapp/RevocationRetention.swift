// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// What an endpoint keeps of a pairing it revoked (RAPP v26.10.18 §4.6
/// item 2): the revocation key, which names the pairing only to its former
/// peer, and when the private key was destroyed, in milliseconds since the
/// Unix epoch.
///
/// The custodian announces the retention for thirty days; the encoded
/// form travels only to the caller's device-only storage.
internal struct RevocationRetention {
  /// Format version of an encoded retention.
  internal static let formatVersion: UInt64 = 1

  internal static let millisecondsPerSecond: UInt64 = 1_000

  private static let millisecondsPerDay: UInt64 = 86_400_000

  private static let announcementDays: UInt64 = 30

  /// How long after a revocation the custodian announces it (§4.6 item 4).
  internal static let announcementMilliseconds = announcementDays * millisecondsPerDay

  private static let expectedKeys = [
    "format_version", "pair_id", "revocation_key", "revoked_at_ms",
  ]

  internal let pairIdentifier: Data

  private let key: RevocationKey

  internal let revokedAtMilliseconds: UInt64

  /// What to keep of `record` before its private key is destroyed, or
  /// `nil` for a degenerate agreement, which is never announced.
  internal init?(record: PairRecord, revokedAtMilliseconds: UInt64) {
    guard let derived = RevocationKey(record: record) else { return nil }
    pairIdentifier = record.pairIdentifier
    key = derived
    self.revokedAtMilliseconds = revokedAtMilliseconds
  }

  private init(pairIdentifier: Data, key: RevocationKey, revokedAtMilliseconds: UInt64) {
    self.pairIdentifier = pairIdentifier
    self.key = key
    self.revokedAtMilliseconds = revokedAtMilliseconds
  }

  /// What a custodian announces at `nowMilliseconds` for `instance` at
  /// `epoch`: the hint and revocation time of each retention still inside
  /// its window.
  internal static func candidates(
    _ retentions: [Self], instance: InstanceName, epoch: UInt64, nowMilliseconds: UInt64
  ) -> [AnnouncementCandidate] {
    retentions
      .filter { $0.announces(atMilliseconds: nowMilliseconds) }
      .map { retention in
        AnnouncementCandidate(
          hint: retention.hint(instance: instance, epoch: epoch),
          lastUsedMilliseconds: retention.revokedAtMilliseconds)
      }
  }

  internal static func decode(_ bytes: Data) throws -> Self {
    var map = try decodedMap(bytes)
    guard map.keys.allSatisfy(expectedKeys.contains) else { throw PairRecordError.invalidInput }
    guard try takeUnsigned(&map, "format_version") == formatVersion else {
      throw PairRecordError.invalidInput
    }
    let decodedPairIdentifier = try takeBytes(&map, "pair_id")
    let decodedKey = try takeBytes(&map, "revocation_key")
    let decodedRevokedAt = try takeUnsigned(&map, "revoked_at_ms")
    guard map.isEmpty, decodedPairIdentifier.count == PairRecordSize.pairIdentifier,
      decodedKey.count == PairKeys.size
    else { throw PairRecordError.invalidInput }
    return Self(
      pairIdentifier: decodedPairIdentifier,
      key: RevocationKey(key: SymmetricKey(data: decodedKey)),
      revokedAtMilliseconds: decodedRevokedAt)
  }

  /// Whether the revocation is still announced at `nowMilliseconds`:
  /// thirty days have not passed, and it is not in the future.
  internal func announces(atMilliseconds nowMilliseconds: UInt64) -> Bool {
    guard nowMilliseconds >= revokedAtMilliseconds else { return false }
    return nowMilliseconds - revokedAtMilliseconds < Self.announcementMilliseconds
  }

  /// Whether the announcement window has run out.
  ///
  /// Then the retention can be destroyed. A clock that has not reached
  /// the revocation's own millisecond is not an expiry.
  internal func isExpired(nowMilliseconds: UInt64) -> Bool {
    guard nowMilliseconds >= revokedAtMilliseconds else { return false }
    return nowMilliseconds - revokedAtMilliseconds >= Self.announcementMilliseconds
  }

  /// The revocation hint for `instance` at `epoch`.
  internal func hint(instance: InstanceName, epoch: UInt64) -> Data {
    key.hint(instance: instance, epoch: epoch)
  }

  /// The deterministic CBOR the caller stores; the key travels inside it.
  internal func encoded() throws -> Data {
    let value = WireValue.map([
      "format_version": .unsigned(Self.formatVersion),
      "pair_id": .bytes(pairIdentifier),
      "revocation_key": .bytes(key.bytes),
      "revoked_at_ms": .unsigned(revokedAtMilliseconds),
    ])
    do {
      return try value.encoded()
    } catch {
      throw PairRecordError.invalidInput
    }
  }
}
