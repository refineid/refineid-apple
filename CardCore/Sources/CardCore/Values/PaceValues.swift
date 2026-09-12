// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The dedicated home for PACE and secure-messaging wire values.
///
/// PACE is the FINEID card's contactless door: the CAN is turned into a
/// shared secret over brainpoolP384r1, and the result is the AES-256
/// session that carries every later APDU. Section references are to ICAO
/// Doc 9303 part 11 (the PACE protocol and its GENERAL AUTHENTICATE data
/// objects) and ISO/IEC 7816-4 (the class byte, the secure-messaging data
/// objects, and padding method 2). Generic 7816-4 values live in
/// `Iso7816Values`; only the PACE-specific and secure-messaging-specific
/// bytes belong here.
///
/// This file is the only sanctioned home for these literals
/// (`.swiftlint.yml` `unexplained_hex`).
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift` and
/// `Sources/RefineIDBrowserKit/Card/SecureMessaging.swift`, which were in
/// turn ported byte-exact from the Rust reference implementation and
/// proven against a live card.
internal enum PaceValues {
  /// The PACE-ECDH-GM-AES-CBC-CMAC-256 object identifier body, without a
  /// DER tag or length: `04 00 7F 00 07 02 02 04 02 04`.
  ///
  /// This is `id-PACE-ECDH-GM-AES-CBC-CMAC-256` under the BSI branch
  /// `0.4.0.127.0.7.2.2.4.2.4` (ICAO 9303-11 section 9.2.1, registered in
  /// BSI TR-03110-3). It names the whole suite the FINEID card offers:
  /// ECDH key agreement, generic mapping, AES-256 in CBC mode for
  /// encryption, and AES-CMAC for integrity. It travels twice -- as the
  /// `80` cryptographic mechanism reference inside MSE:Set AT, and inside
  /// the mutual-authentication token input.
  /// It is assembled from the individually named arc bytes below rather
  /// than written as a hex literal, so every byte carries its meaning.
  internal static let protocolOidBody: [UInt8] = [
    oidArcItuTIdentifiedOrganization,
    oidArcEtsi,
    oidArcReserved,
    oidArcInternational,
    oidArcBsiDe,
    oidArcProtocols,
    oidArcSmartcard,
    oidArcIdPace,
    oidArcEcdhGenericMapping,
    oidArcAesCbcCmac256,
  ]

  /// OID byte 1: arcs `itu-t(0) identified-organization(4)`, packed into
  /// a single byte as `40 * 0 + 4` (X.690 section 8.19.4).
  private static let oidArcItuTIdentifiedOrganization: UInt8 = 0x04

  /// OID byte 2: arc `etsi(0)`.
  private static let oidArcEtsi: UInt8 = 0x00

  /// OID byte 3: arc `reserved(127)`, the branch delegated to national
  /// bodies.
  private static let oidArcReserved: UInt8 = 0x7F

  /// OID byte 4: arc `etsi-identified-organization(0)`.
  private static let oidArcInternational: UInt8 = 0x00

  /// OID byte 5: arc `bsi-de(7)`, completing `0.4.0.127.0.7`, the German
  /// BSI root under which TR-03110-3 registers these protocols.
  private static let oidArcBsiDe: UInt8 = 0x07

  /// OID byte 6: arc `protocols(2)`.
  private static let oidArcProtocols: UInt8 = 0x02

  /// OID byte 7: arc `smartcard(2)`.
  private static let oidArcSmartcard: UInt8 = 0x02

  /// OID byte 8: arc `id-PACE(4)`, naming the PACE protocol family.
  private static let oidArcIdPace: UInt8 = 0x04

  /// OID byte 9: arc `id-PACE-ECDH-GM(2)`, selecting ECDH key agreement
  /// with generic mapping.
  private static let oidArcEcdhGenericMapping: UInt8 = 0x02

  /// OID byte 10: arc `id-PACE-ECDH-GM-AES-CBC-CMAC-256(4)`, fixing the
  /// cipher at AES-256 in CBC mode with an AES-CMAC checksum.
  private static let oidArcAesCbcCmac256: UInt8 = 0x04

  /// Tag `80` inside the MSE:Set AT template: the cryptographic
  /// mechanism reference, whose value is `protocolOidBody`
  /// (ISO 7816-4 section 5.4.2; ICAO 9303-11 section 9.2.1).
  ///
  /// The same byte value tags a different object inside `7C`; the two
  /// contexts are named separately so neither is read as the other.
  internal static let cryptographicMechanismReferenceTag: UInt8 = 0x80

  /// Tag `83` inside the MSE:Set AT template: the password reference,
  /// selecting which shared secret PACE runs with
  /// (ICAO 9303-11 section 9.2.1).
  internal static let passwordReferenceTag: UInt8 = 0x83

  /// Tag `84` inside the MSE:Set AT template: the domain parameter
  /// reference, selecting the curve (ICAO 9303-11 section 9.2.1).
  internal static let domainParameterReferenceTag: UInt8 = 0x84

  /// Tag `06`, the DER OBJECT IDENTIFIER that carries
  /// `protocolOidBody` inside the mutual-authentication token input
  /// (ITU-T X.690 section 8.19).
  internal static let objectIdentifierTag: UInt8 = 0x06

  /// The first byte of tag `7F49`, the public key template that the
  /// mutual-authentication token is computed over
  /// (ICAO 9303-11 section 9.4.4; BSI TR-03110-3).
  ///
  /// The tag is two bytes because bits 1-5 of the first byte are all
  /// set, which ISO 8825 reads as "the tag number continues". The
  /// encoder therefore emits this byte and then encodes the object under
  /// the second byte, which produces `7F 49 <len> <value>` exactly.
  internal static let publicKeyTemplateTagFirstByte: UInt8 = 0x7F

  /// The second byte of tag `7F49`.
  internal static let publicKeyTemplateTagSecondByte: UInt8 = 0x49

  /// Tag `86` inside `7F49`: the public point the authentication token is
  /// computed over (ICAO 9303-11 section 9.4.4).
  ///
  /// The same byte value tags the card's authentication token inside `7C`;
  /// the two contexts are named separately so neither is read as the other.
  internal static let publicKeyTemplatePointTag: UInt8 = 0x86

  /// GENERAL AUTHENTICATE P1: no algorithm reference given, the
  /// environment set by MSE:Set AT applies (ICAO 9303-11 section 9.2).
  internal static let generalAuthenticateP1: UInt8 = 0x00

  /// GENERAL AUTHENTICATE P2: no key reference given, likewise taken
  /// from the authentication template (ICAO 9303-11 section 9.2).
  internal static let generalAuthenticateP2: UInt8 = 0x00

  /// Password reference for the CAN, sent in the MSE:Set AT `83` data
  /// object (ICAO 9303-11 section 9.2.1 Table: 1 = MRZ, 2 = CAN,
  /// 3 = PIN, 4 = PUK).
  ///
  /// RefineID only ever authenticates with the CAN, the six digits
  /// printed on the card.
  internal static let passwordReferenceCan: UInt8 = 0x02

  /// Domain parameter reference for brainpoolP384r1, sent in the
  /// MSE:Set AT `84` data object (ICAO 9303-11 section 9.2.1; the
  /// standardized domain parameter table of BSI TR-03110-3 assigns
  /// 13 = brainpoolP256r1, 16 = brainpoolP384r1).
  internal static let domainParameterReferenceBrainpoolP384r1: UInt8 = 0x10

  /// GENERAL AUTHENTICATE instruction byte (ISO 7816-4 section 11.5.4;
  /// ICAO 9303-11 section 9.2).
  ///
  /// Every PACE round after MSE:Set AT is a GENERAL AUTHENTICATE; the
  /// first three are command-chained and the last is not.
  internal static let insGeneralAuthenticate: UInt8 = 0x86

  /// MANAGE SECURITY ENVIRONMENT P1 for PACE: SET, with the verification,
  /// encipherment, external authentication and key agreement bits set
  /// (ICAO 9303-11 section 9.2.1).
  internal static let mseSetAuthenticationTemplateP1: UInt8 = 0xC1

  /// MANAGE SECURITY ENVIRONMENT P2 for PACE: the Authentication
  /// Template (AT) control reference template tag, `A4`
  /// (ISO 7816-4 section 5.4.2; ICAO 9303-11 section 9.2.1).
  internal static let mseSetAuthenticationTemplateP2: UInt8 = 0xA4

  /// The secure-messaging bits of the class byte: `0000 11xx`, meaning
  /// secure messaging with the command header authenticated
  /// (ISO 7816-4 section 5.1.1 Table 2).
  ///
  /// Set into the plain command's CLA when a command is wrapped, which is
  /// exactly why the header itself must be covered by the MAC.
  internal static let classSecureMessagingBit: UInt8 = 0x0C

  /// Secure-messaging DO'85': the cryptogram used for command or response
  /// data when the original instruction byte is odd.
  ///
  /// Unlike DO'87', its value does not carry a padding-content indicator
  /// (ISO 7816-4 section 5.6.3 Table 22).
  internal static let oddInstructionCryptogramTag: UInt8 = 0x85

  /// Secure-messaging DO'87': padding-content indicator byte followed by
  /// the cryptogram, used when the original instruction byte is even
  /// (ISO 7816-4 section 5.6.3 Table 22).
  internal static let cryptogramTag: UInt8 = 0x87

  /// Secure-messaging DO'97': the Le of the enclosed plain command
  /// (ISO 7816-4 section 5.6.3 Table 22).
  internal static let expectedLengthTag: UInt8 = 0x97

  /// Secure-messaging DO'99': the status word of the enclosed plain
  /// response (ISO 7816-4 section 5.6.3 Table 22).
  ///
  /// This data object is not optional: the real SW never travels in the
  /// clear, so a response without a verified DO'99' has no status at all.
  internal static let statusTag: UInt8 = 0x99

  /// Secure-messaging DO'8E': the cryptographic checksum, here an
  /// AES-CMAC (ISO 7816-4 section 5.6.3 Table 22).
  internal static let macTag: UInt8 = 0x8E

  /// The padding-content indicator that opens DO'87': `01` means the
  /// plaintext was padded per ISO 7816-4 padding method 2
  /// (ISO 7816-4 section 5.6.3 Table 23).
  internal static let paddingContentIndicator: UInt8 = 0x01

  /// The ISO 7816-4 padding method 2 marker byte: append `80`, then `00`
  /// up to the block boundary (ISO 7816-4 section 5.6.3 / Annex).
  ///
  /// Padding is unconditional -- an already-aligned buffer gains a whole
  /// extra block -- so that stripping it is unambiguous.
  internal static let paddingMarkerByte: UInt8 = 0x80

  /// The bytes of AES-CMAC kept for DO'8E': the tag is truncated to its
  /// leading 8 bytes (ICAO 9303-11 section 9.8.2; BSI TR-03110-3).
  internal static let macLength: Int = 8

  /// The length in bytes of the send-sequence counter, one AES block
  /// (ICAO 9303-11 section 9.8.7).
  ///
  /// The SSC starts at zero after PACE and pre-increments in both
  /// directions, so a command uses SSC = 1 and its response SSC = 2. Its
  /// encryption under Kenc is also the CBC initialization vector.
  internal static let sendSequenceCounterLength: Int = 16

  /// Tag `7C`, the Dynamic Authentication Data template that wraps the
  /// payload of every GENERAL AUTHENTICATE in both directions
  /// (ISO 7816-4 section 5.4.2; ICAO 9303-11 section 9.2).
  internal static let dynamicAuthenticationDataTag: UInt8 = 0x7C

  /// Context tag `80` inside `7C`: the encrypted nonce returned by the
  /// card in PACE step 1 (ICAO 9303-11 section 9.2 Table).
  ///
  /// Deciphering it with the key derived from the CAN is what proves the
  /// CAN was known.
  internal static let encryptedNonceTag: UInt8 = 0x80

  /// Context tag `81` inside `7C`: the terminal's (PCD's) mapping data,
  /// its ephemeral public point for the generic mapping
  /// (ICAO 9303-11 section 9.2 Table).
  internal static let mappingDataTerminalTag: UInt8 = 0x81

  /// Context tag `82` inside `7C`: the card's (PICC's) mapping data
  /// (ICAO 9303-11 section 9.2 Table).
  internal static let mappingDataCardTag: UInt8 = 0x82

  /// Context tag `83` inside `7C`: the terminal's ephemeral public key on
  /// the mapped generator (ICAO 9303-11 section 9.2 Table).
  internal static let ephemeralPublicKeyTerminalTag: UInt8 = 0x83

  /// Context tag `84` inside `7C`: the card's ephemeral public key on the
  /// mapped generator (ICAO 9303-11 section 9.2 Table).
  internal static let ephemeralPublicKeyCardTag: UInt8 = 0x84

  /// Context tag `85` inside `7C`: the terminal's authentication token,
  /// the truncated CMAC over the card's public point
  /// (ICAO 9303-11 section 9.2 Table).
  internal static let authenticationTokenTerminalTag: UInt8 = 0x85

  /// Context tag `86` inside `7C`: the card's authentication token, which
  /// the terminal recomputes and compares in constant time
  /// (ICAO 9303-11 section 9.2 Table).
  ///
  /// A mismatch means the session keys differ and the channel must be
  /// abandoned, not retried on the same keys.
  internal static let authenticationTokenCardTag: UInt8 = 0x86
}
