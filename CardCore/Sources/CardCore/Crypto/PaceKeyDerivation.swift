// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The PACE key derivation function of ICAO Doc 9303 Part 11 section 9.7.1.2,
/// in its AES-256 form.
///
/// The function is `SHA-256(secret || counter)`, the counter appended as a
/// big-endian 32-bit word, and the digest is taken whole as the AES-256 key
/// with no truncation. Three counters cover the protocol: the password key
/// unlocks the encrypted nonce, and the two session keys protect everything
/// after mutual authentication succeeds.
///
/// Only the SHA-256 form exists here. Doc 9303 also defines a SHA-1 form for
/// 3DES and AES-128, but the FINEID card's PACE profile is AES-256, and an
/// unexercised second hash path is a liability rather than completeness.
///
/// The secret and the derived keys are key material: neither may be logged,
/// formatted, or persisted.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/KDF.swift`.
internal enum PaceKeyDerivation {
  /// Which of the three PACE keys a derivation produces.
  ///
  /// The raw value is the Doc 9303 counter appended to the secret, so the
  /// enumeration is the only place those numbers appear.
  internal enum KeyKind: UInt32 {
    /// The secure-messaging encryption key, counter one.
    case encryption = 1

    /// The secure-messaging authentication key, counter two.
    case mac = 2

    /// The key derived from the shared password that decrypts the PACE
    /// nonce, counter three.
    case password = 3
  }

  /// The derived key length in bytes: the whole SHA-256 digest, which is
  /// exactly an AES-256 key.
  internal static let derivedKeyLength = SHA256.byteCount

  /// Derives one PACE key from `secret`.
  ///
  /// For the session keys `secret` is the shared secret agreed by the key
  /// agreement; for `password` it is the encoded password, and the card
  /// access number that produced it must never outlive the derivation.
  internal static func derivedKey(from secret: Data, for kind: KeyKind) -> Data {
    var input = secret
    withUnsafeBytes(of: kind.rawValue.bigEndian) { counterBytes in
      input.append(contentsOf: counterBytes)
    }
    return Data(SHA256.hash(data: input))
  }
}
