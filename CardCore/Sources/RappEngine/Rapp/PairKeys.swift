// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Keys both endpoints of a pairing derive from its static X25519
/// agreement (RAPP v26.10.21 §4.3).
///
/// The agreement never crosses the wire, so a value keyed by it names the
/// pairing only to its two endpoints. Each use takes its own HKDF info
/// label.
internal enum PairKeys {
  /// Byte length of every key derived from the static agreement.
  internal static let size = 32

  internal static let routingInfo = Data("rapp-routing".utf8)
  internal static let discoveryInfo = Data("rapp-discovery-hint".utf8)
  internal static let withdrawalInfo = Data("rapp-withdrawal".utf8)

  /// `HKDF-SHA-256(salt = pair_id, IKM = X25519(local static private,
  /// peer static public), info, L = 32)`, or `nil` when the agreement is
  /// the identity point.
  internal static func derive(
    pairIdentifier: Data,
    localStaticPrivate: Data,
    remoteStaticPublic: Data,
    info: Data
  ) -> SymmetricKey? {
    guard
      let local = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: localStaticPrivate),
      let remote = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteStaticPublic),
      let agreement = try? local.sharedSecretFromKeyAgreement(with: remote)
    else { return nil }
    let degenerate = agreement.withUnsafeBytes { bytes in bytes.allSatisfy { $0 == 0 } }
    guard !degenerate else { return nil }
    return agreement.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: pairIdentifier, sharedInfo: info, outputByteCount: size)
  }

  /// `HMAC-SHA-256(key, parts)`, the full 32-byte output.
  internal static func mac(_ key: SymmetricKey, _ parts: [Data]) -> Data {
    var hmac = HMAC<SHA256>(key: key)
    for part in parts {
      hmac.update(data: part)
    }
    return Data(hmac.finalize())
  }

  /// The big-endian octets of `value`.
  internal static func bigEndian(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
  }

  /// Whether `left` and `right` hold the same octets, in time independent
  /// of where they differ.
  internal static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for (first, second) in zip(left, right) {
      difference |= first ^ second
    }
    return difference == 0
  }
}
