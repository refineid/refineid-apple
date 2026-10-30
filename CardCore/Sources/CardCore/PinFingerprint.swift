// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit

/// A non-reversible, process-local fingerprint of one PIN bound to one
/// card serial and one credential role.
///
/// The digest is salted with a random value generated once per process:
/// fingerprints are comparable only within this process lifetime, which is
/// exactly the lifetime of the rejected-PIN memory. The raw PIN is never
/// stored. CryptoKit is the platform's hash implementation; a non-Apple
/// build would swap in swift-crypto's identical API.
public struct PinFingerprint: Equatable, Hashable, Sendable {
  /// Number of random salt bytes drawn once per process.
  private static let saltByteCount: Int = 32

  /// Separates variable-length fields in the hashed material so field
  /// boundaries cannot be confused.
  private static let fieldSeparator: UInt8 = 0

  /// Process-lifetime random salt.
  private static let processSalt: [UInt8] = (0..<saltByteCount).map { _ in
    UInt8.random(in: .min ... .max)
  }

  /// Domain-separation tag for PIN1.
  private static let pin1Tag: UInt8 = 1

  /// Domain-separation tag for PIN2.
  private static let pin2Tag: UInt8 = 2

  /// Domain-separation tag for the PUK.
  private static let pukTag: UInt8 = 3

  private let digest: [UInt8]

  /// Computes the fingerprint over salt, role, full serial, and digits;
  /// with no serial, the fingerprint is bound to no card.
  ///
  /// A serial is never empty and starts with a printable byte, so the
  /// separator that follows the role in a card-free fingerprint cannot
  /// collide with a card-bound one's material.
  ///
  /// Internal: only credential types construct fingerprints of themselves.
  internal static func compute(
    digits: ZeroizingDigitStore,
    serial: ChipSerial?,
    role: CredentialRole
  ) -> Self {
    var material: [UInt8] = []
    material.append(contentsOf: Self.processSalt)
    material.append(Self.roleTag(role))
    if let serial {
      material.append(contentsOf: Array(serial.value.utf8))
    }
    material.append(Self.fieldSeparator)
    material.append(contentsOf: digits.bytes)
    defer {
      for index in material.indices {
        material[index] = 0
      }
    }
    return Self(digest: Array(SHA256.hash(data: material)))
  }

  /// Stable one-byte domain separator per credential role.
  private static func roleTag(_ role: CredentialRole) -> UInt8 {
    switch role {
    case .pin1:
      pin1Tag

    case .pin2:
      pin2Tag

    case .puk:
      pukTag
    }
  }
}
