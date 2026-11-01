// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The dedicated home for ISO 7816-4 wire values.
///
/// Every constant is named and documented here exactly once; no other
/// production or test file may carry a raw hex literal
/// (`.swiftlint.yml` `unexplained_hex`). Section references are to
/// ISO/IEC 7816-4; FINEID-specific values live in `FineidValues`.
internal enum Iso7816Values {
  /// Plain interindustry class byte, no secure messaging, channel 0.
  internal static let classInterindustry: UInt8 = 0x00

  /// Class byte bit 5, command chaining: more command APDUs follow
  /// before the card may act (7816-4 §5.1.1 Table 1).
  ///
  /// The first three PACE GENERAL AUTHENTICATE rounds set it; the last
  /// one clears it, which is how the card knows the exchange is over.
  internal static let classCommandChaining: UInt8 = 0x10

  /// SELECT instruction (7816-4 §11.1.1).
  internal static let insSelect: UInt8 = 0xA4

  /// READ BINARY instruction (7816-4 §11.2.2).
  internal static let insReadBinary: UInt8 = 0xB0

  /// VERIFY instruction (7816-4 §11.5.6; FINEID S1 v4.2 §3.5).
  internal static let insVerify: UInt8 = 0x20

  /// CHANGE REFERENCE DATA instruction (7816-4 §11.5.7; FINEID S1 v4.2
  /// §3.5.3).
  internal static let insChangeReferenceData: UInt8 = 0x24

  /// RESET RETRY COUNTER instruction (7816-4 §11.5.10; FINEID S1 v4.2
  /// §3.5.4).
  internal static let insResetRetryCounter: UInt8 = 0x2C

  /// CHANGE REFERENCE DATA P1: the data field carries the current
  /// reference data followed by the new (7816-4 §11.5.7).
  internal static let changeCurrentThenNewP1: UInt8 = 0x00

  /// RESET RETRY COUNTER P1: the data field carries the unblocking key
  /// followed by the new reference data (7816-4 §11.5.10).
  internal static let resetWithPukThenNewP1: UInt8 = 0x00

  /// RESET RETRY COUNTER P1: the data field carries only the new
  /// reference data; the unblocking credential was verified as its own
  /// object beforehand (7816-4 §11.5.10; Idemia organizational cards
  /// specification §4.1.6).
  internal static let resetNewDataOnlyP1: UInt8 = 0x02

  /// GET DATA instruction, odd variant (FINEID S1 v4.2 §3.15.2).
  internal static let insGetData: UInt8 = 0xCB

  /// GET RESPONSE instruction (7816-4 §11.7.1; T=0 continuation).
  internal static let insGetResponse: UInt8 = 0xC0

  /// MANAGE SECURITY ENVIRONMENT instruction (FINEID S1 v4.2 §3.6).
  internal static let insManageSecurityEnvironment: UInt8 = 0x22

  /// PERFORM SECURITY OPERATION instruction (FINEID S1 v4.2 §3.8).
  internal static let insPerformSecurityOperation: UInt8 = 0x2A

  /// MSE P1: SET for computation and deciphering (S1 v4.2 §3.6.2).
  internal static let mseSetP1: UInt8 = 0x41

  /// MSE P2: Digital Signature Template (S1 v4.2 §3.6.2 Table 5).
  internal static let mseDigitalSignatureTemplateP2: UInt8 = 0xB6

  /// PSO:CDS P1: return the digital-signature data object
  /// (S1 v4.2 §3.8.2).
  internal static let psoComputeSignatureP1: UInt8 = 0x9E

  /// PSO:CDS P2: the data field contains the data to be signed
  /// (S1 v4.2 §3.8.2).
  internal static let psoComputeSignatureP2: UInt8 = 0x9A

  /// PSO:HASH P1: set the hash to be used by the next PSO:CDS
  /// (S1 v4.2 §3.7.2).
  internal static let psoHashP1: UInt8 = 0x90

  /// PSO:HASH P2: the data field carries the complete hash value,
  /// computed externally (S1 v4.2 §3.7.2).
  internal static let psoHashExternalP2: UInt8 = 0xA0

  /// PSO:HASH data-object tag for the externally-computed hash value:
  /// the body is `90 <len> <hash>` (S1 v4.2 §3.7.2).
  internal static let psoHashValueTag: UInt8 = 0x90

  /// SW family `0x6Cxx`: wrong Le, SW2 is the exact available length.
  ///
  /// The card answers PSO:CDS `Le=00` with `6C60` for a 96-byte P-384
  /// signature and the command is re-issued with the exact Le.
  internal static let swWrongLengthPrefix: UInt16 = 0x6C00

  /// SW family `0x61xx`: response bytes available via GET RESPONSE;
  /// SW2 carries the count (0 meaning 256 or more).
  internal static let swResponseAvailablePrefix: UInt16 = 0x6100

  /// Mask selecting SW1, to test family membership.
  internal static let swFamilyMask: UInt16 = 0xFF00

  /// DER universal tag: SEQUENCE.
  internal static let derSequenceTag: UInt8 = 0x30

  /// DER universal tag: INTEGER.
  internal static let derIntegerTag: UInt8 = 0x02

  /// DER universal tag: OCTET STRING.
  internal static let derOctetStringTag: UInt8 = 0x04

  /// Tag of PKCS#15's context-specific `label [0]` field in TokenInfo.
  internal static let derContextLabelTag: UInt8 = 0x80

  /// DER tag for a UTF8String, which PKCS#15 uses for its labels.
  internal static let derUtf8StringTag: UInt8 = 0x0C

  /// DER length byte: long-form marker bit.
  internal static let derLongFormMask: UInt8 = 0x80

  /// DER length byte: number-of-length-bytes mask in long form.
  internal static let derLengthCountMask: UInt8 = 0x7F

  /// SELECT P1: select by DF name (application identifier).
  internal static let selectByAidP1: UInt8 = 0x04

  /// SELECT P1: select EF by file identifier under the current DF
  /// (FINEID S1 v4.2 §3.2.2).
  internal static let selectEfUnderCurrentDfP1: UInt8 = 0x02

  /// SELECT P1: select MF, DF or EF by file identifier (7816-4).
  internal static let selectByFileIdP1: UInt8 = 0x00

  /// SELECT P1: select a child DF under the current DF (7816-4).
  internal static let selectChildDfP1: UInt8 = 0x01

  /// SELECT P2: first-or-only occurrence, return no FCI.
  internal static let selectByAidNoFciP2: UInt8 = 0x0C

  /// SELECT P2: return no response data (FINEID S1 v4.2 §3.2.2).
  internal static let selectNoResponseP2: UInt8 = 0x0C

  /// VERIFY P1: verify mode (FINEID S1 v4.2 §3.5.2).
  internal static let verifyModeP1: UInt8 = 0x00

  /// Le encoding for "maximum" in a short APDU: 0x00 means 256.
  internal static let expectedLengthMaximumEncoding: UInt8 = 0x00

  /// Highest READ BINARY offset encodable in P1-P2 with bit 8 of P1
  /// clear (15-bit direct offset).
  internal static let readBinaryOffsetMaximum: UInt16 = 0x7FFF

  /// Mask selecting the low byte of a 16-bit value.
  internal static let lowByteMask: UInt16 = 0x00FF

  /// Mask selecting the low nibble of a byte (the 63Cx counter).
  internal static let lowNibbleMask: UInt8 = 0x0F

  /// Bit width of one byte, for SW1/P1 shifts.
  internal static let byteShift: Int = 8

  /// Radix for parsing hexadecimal digit strings.
  internal static let hexRadix: Int = 16

  /// SW `0x9000`: normal processing, no further information.
  internal static let swSuccess: UInt16 = 0x9000

  /// SW `0x6282`: end of file reached before Le bytes.
  internal static let swEndOfFile: UInt16 = 0x6282

  /// SW `0x6300`: authentication failed without a retry counter.
  internal static let swAuthenticationFailed: UInt16 = 0x6300

  /// SW `0x6700`: wrong length (Lc inconsistent with the command).
  internal static let swWrongLength: UInt16 = 0x6700

  /// SW `0x6982`: security status not satisfied.
  internal static let swSecurityNotSatisfied: UInt16 = 0x6982

  /// SW `0x6985`: conditions of use not satisfied (ISO/IEC 7816-4).
  internal static let swConditionsNotSatisfied: UInt16 = 0x6985

  /// SW `0x6983`: authentication method blocked (counter exhausted).
  internal static let swAuthenticationBlocked: UInt16 = 0x6983

  /// SW `0x6984`: referenced data invalidated.
  internal static let swReferenceDataInvalidated: UInt16 = 0x6984

  /// SW `0x6988`: secure-messaging data objects incorrect.
  internal static let swSmDataObjectsIncorrect: UInt16 = 0x6988

  /// SW `0x6999`: the card refuses the command outright.
  ///
  /// Measured on the contactless interface: a session that ended with a
  /// PACE channel still open leaves the card answering this to the next
  /// approach until it is met again in a fresh session.
  internal static let swStaleSecureChannel: UInt16 = 0x6999

  /// SW `0x6A82`: file or application not found.
  internal static let swFileNotFound: UInt16 = 0x6A82

  /// SW `0x6A88`: referenced data not found.
  internal static let swReferenceDataNotFound: UInt16 = 0x6A88

  /// SW family `0x63Cx`: verification failed, low nibble of SW2 is the
  /// retry counter (7816-4 §5.6).
  internal static let swPinCounterPrefix: UInt16 = 0x63C0

  /// Mask selecting the high 12 bits, to test membership in the
  /// `0x63Cx` family independently of the counter nibble.
  internal static let swPinCounterMask: UInt16 = 0xFFF0
}
