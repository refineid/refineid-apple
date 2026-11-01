// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// This file is a registry table: every number below is an arc or a
// selector assigned by the documents named on it, and the tables exist
// to be read against those documents. Naming each arc separately would
// hide the pattern the table exists to show -- which identifiers differ
// only by their mapping, and which domain parameters are cheaper than
// the one in use. The cases are in registered arc order for the same
// reason.
/// The tags, arcs and registered identifiers EF.CardAccess is written
/// in (ICAO 9303-11 section 9.2.11; BSI TR-03110-3 appendix A).
internal enum CardAccessValues {
  /// How the card derives the mapped generator, arc 9 of a PACE
  /// identifier (BSI TR-03110-3 appendix A.1.1).
  ///
  /// The mapping is the reason to read this file at all: generic
  /// mapping costs the card a Diffie-Hellman it does not owe under
  /// integrated mapping.
  internal enum Mapping: UInt8 {
    /// `id-PACE-DH-GM(1)`: finite-field DH, generic mapping.
    case diffieHellmanGeneric = 0x01

    /// `id-PACE-ECDH-GM(2)`: elliptic-curve DH, generic mapping.
    case ellipticGeneric = 0x02

    /// `id-PACE-DH-IM(3)`: finite-field DH, integrated mapping.
    case diffieHellmanIntegrated = 0x03

    /// `id-PACE-ECDH-IM(4)`: elliptic-curve DH, integrated mapping.
    case ellipticIntegrated = 0x04

    /// `id-PACE-ECDH-CAM(6)`: elliptic-curve DH, chip-authentication
    /// mapping.
    case ellipticChipAuthentication = 0x06

    /// What this mapping is called in the specification.
    internal var name: String {
      switch self {
      case .diffieHellmanGeneric:
        "DH-GM"

      case .ellipticGeneric:
        "ECDH-GM"

      case .diffieHellmanIntegrated:
        "DH-IM"

      case .ellipticIntegrated:
        "ECDH-IM"

      case .ellipticChipAuthentication:
        "ECDH-CAM"
      }
    }

    /// Whether this mapping spares the card the mapping Diffie-Hellman.
    internal var isIntegrated: Bool {
      self == .diffieHellmanIntegrated || self == .ellipticIntegrated
    }
  }

  /// The secure-messaging cipher, arc 10 of a PACE identifier
  /// (BSI TR-03110-3 appendix A.1.1).
  internal enum Cipher: UInt8 {
    /// `3DES-CBC-CBC(1)`.
    case tripleDes = 0x01

    /// `AES-CBC-CMAC-128(2)`.
    case aes128 = 0x02

    /// `AES-CBC-CMAC-192(3)`.
    case aes192 = 0x03

    /// `AES-CBC-CMAC-256(4)`.
    case aes256 = 0x04

    /// What this cipher is called in the specification.
    internal var name: String {
      switch self {
      case .tripleDes:
        "3DES-CBC-CBC"

      case .aes128:
        "AES-CBC-CMAC-128"

      case .aes192:
        "AES-CBC-CMAC-192"

      case .aes256:
        "AES-CBC-CMAC-256"
      }
    }
  }

  /// Tag `31`, the DER SET that wraps every SecurityInfo
  /// (ITU-T X.690 section 8.12).
  internal static let setTag: UInt8 = 0x31

  /// Tag `30`, the DER SEQUENCE one SecurityInfo is
  /// (ITU-T X.690 section 8.9).
  internal static let sequenceTag: UInt8 = 0x30

  /// Tag `06`, the DER OBJECT IDENTIFIER naming the protocol
  /// (ITU-T X.690 section 8.19).
  internal static let objectIdentifierTag: UInt8 = 0x06

  /// Tag `02`, the DER INTEGER carrying a version or a parameter id
  /// (ITU-T X.690 section 8.3).
  internal static let integerTag: UInt8 = 0x02

  /// The sign bit of the first content octet of a DER INTEGER
  /// (ITU-T X.690 section 8.3.3).
  internal static let integerSignBit: UInt8 = 0x80

  /// The leading octet a DER INTEGER carries only to clear the sign bit of
  /// the octet after it (ITU-T X.690 section 8.3.2).
  internal static let integerPadOctet: UInt8 = 0x00

  /// The leading octet a DER INTEGER carries only to set the sign bit of
  /// the octet after it (ITU-T X.690 section 8.3.2).
  internal static let integerSignExtensionOctet: UInt8 = 0xFF

  /// The `0.4.0.127.0.7.2.2` prefix every BSI smart-card protocol
  /// identifier opens with, in DER content bytes.
  ///
  /// The first byte is the two leading arcs combined as `40 * 0 + 4`
  /// (ITU-T X.690 section 8.19.4); the rest are one arc each.
  internal static let bsiSmartcardPrefix: [UInt8] = [0x04, 0x00, 0x7F, 0x00, 0x07, 0x02, 0x02]

  /// Arc `id-PACE(4)`, the family this file is read to enumerate.
  internal static let familyPace: UInt8 = 0x04

  /// How many arcs follow the prefix in a PACE identifier: family,
  /// mapping and cipher.
  internal static let paceArcCount: Int = 3

  /// Offset of the family arc after the prefix.
  internal static let paceFamilyOffset: Int = 0

  /// Offset of the mapping arc after the prefix.
  internal static let paceMappingOffset: Int = 1

  /// Offset of the cipher arc after the prefix.
  internal static let paceCipherOffset: Int = 2

  /// Highest arc value that fits one DER identifier byte; above this an
  /// arc continues into further bytes (ITU-T X.690 section 8.19.2).
  internal static let objectIdentifierContinuation: UInt8 = 0x80

  /// The seven low bits each identifier byte contributes.
  internal static let objectIdentifierValueMask: UInt8 = 0x7F

  /// How far a decoded arc shifts left before the next seven bits.
  internal static let objectIdentifierShift: Int = 7

  /// Divisor combining the first two arcs into one byte.
  internal static let objectIdentifierFirstArcScale: Int = 40

  /// The registered `parameterId` values, smallest field first
  /// (BSI TR-03110-3 appendix A.2.1.1).
  ///
  /// The name carries the field size because that is what the card's
  /// scalar multiplication costs scale with, and reading EF.CardAccess
  /// is how a cheaper curve would be found.
  private static let domainParameters: [Int: String] = [
    0: "1024-bit MODP group with 160-bit prime order subgroup",
    1: "2048-bit MODP group with 224-bit prime order subgroup",
    2: "2048-bit MODP group with 256-bit prime order subgroup",
    8: "NIST P-192 (secp192r1)",
    9: "brainpoolP192r1",
    10: "NIST P-224 (secp224r1)",
    11: "brainpoolP224r1",
    12: "NIST P-256 (secp256r1)",
    13: "brainpoolP256r1",
    14: "brainpoolP320r1",
    15: "NIST P-384 (secp384r1)",
    16: "brainpoolP384r1",
    17: "brainpoolP512r1",
    18: "NIST P-521 (secp521r1)",
  ]

  /// What a `parameterId` names, or nil when this build has no name for
  /// it.
  internal static func domainParameterName(_ identifier: Int) -> String? {
    Self.domainParameters[identifier]
  }
}
