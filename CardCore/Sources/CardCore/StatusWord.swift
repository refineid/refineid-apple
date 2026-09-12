// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Decoded ISO 7816-4 status word, typed after the Rust reference
/// implementation's classification.
///
/// Coverage is specific to what RefineID uses: when a new layer matches
/// on an additional SW, add a case here rather than a raw literal.
/// Unrecognised values land in `other` carrying the raw 16-bit word -
/// unknown never silently maps to a valid state
public enum StatusWord: Equatable, Sendable {
  /// `6983`: authentication method blocked - the credential is locked.
  case authenticationBlocked

  /// `6300`: verification failed without a retry counter.
  case authenticationFailed

  /// `6282`: end of file reached before the requested Le bytes; the
  /// returned payload up to the boundary is still valid.
  case endOfFile

  /// `6A82`: file or application not found.
  case fileNotFound

  /// Any status word RefineID does not model, carried verbatim.
  case other(UInt16)

  /// `63Cx`: verification failed or probed; `remaining` is the retry
  /// counter from the low nibble of SW2.
  case pinIncorrect(remaining: RetryCount)

  /// `6984`: referenced data invalidated.
  case referenceDataInvalidated

  /// `6A88`: referenced data not found.
  case referenceDataNotFound

  /// `61xx`: response bytes available via GET RESPONSE; `count` is SW2
  /// (zero meaning 256 or more). T=0 transports surface this instead of
  /// delivering the payload directly.
  case responseAvailable(count: UInt8)

  /// `6982`: security status not satisfied.
  case securityNotSatisfied

  /// `6988`: secure-messaging data objects incorrect.
  case smDataObjectsIncorrect

  /// `6999`: the card refuses the command outright.
  ///
  /// Measured meaning on the contactless interface: a previous session
  /// ended with the PACE secure channel still open on the card, and it
  /// refuses the next approach with this until it is met in a fresh
  /// session. One retry recovers it; a second never has.
  case staleSecureChannel

  /// `9000`: normal processing.
  case success

  /// `6Cxx`: wrong Le; `availableLength` is SW2, the exact length to
  /// re-issue with.
  ///
  /// PSO:CDS answers `6C60` for a 96-byte P-384 signature; the command
  /// is re-sent with that Le.
  case wrongExpectedLength(availableLength: UInt8)

  /// `6700`: wrong length.
  case wrongLength

  /// One-to-one classifications; the `63Cx` counter family is handled
  /// separately because it carries a value.
  private static let simpleClassifications: [UInt16: Self] = [
    Iso7816Values.swSuccess: .success,
    Iso7816Values.swEndOfFile: .endOfFile,
    Iso7816Values.swAuthenticationFailed: .authenticationFailed,
    Iso7816Values.swWrongLength: .wrongLength,
    Iso7816Values.swSecurityNotSatisfied: .securityNotSatisfied,
    Iso7816Values.swAuthenticationBlocked: .authenticationBlocked,
    Iso7816Values.swReferenceDataInvalidated: .referenceDataInvalidated,
    Iso7816Values.swSmDataObjectsIncorrect: .smDataObjectsIncorrect,
    Iso7816Values.swStaleSecureChannel: .staleSecureChannel,
    Iso7816Values.swFileNotFound: .fileNotFound,
    Iso7816Values.swReferenceDataNotFound: .referenceDataNotFound,
  ]

  /// The raw 16-bit wire value; inverse of `init(sw1:sw2:)`.
  public var encoded: UInt16 {
    switch self {
    case .authenticationBlocked:
      Iso7816Values.swAuthenticationBlocked

    case .authenticationFailed:
      Iso7816Values.swAuthenticationFailed

    case .endOfFile:
      Iso7816Values.swEndOfFile

    case .fileNotFound:
      Iso7816Values.swFileNotFound

    case .other(let value):
      value

    case .pinIncorrect(let remaining):
      Iso7816Values.swPinCounterPrefix | UInt16(remaining.attemptsRemaining)

    case .referenceDataInvalidated:
      Iso7816Values.swReferenceDataInvalidated

    case .referenceDataNotFound:
      Iso7816Values.swReferenceDataNotFound

    case .responseAvailable(let count):
      Iso7816Values.swResponseAvailablePrefix | UInt16(count)

    case .securityNotSatisfied:
      Iso7816Values.swSecurityNotSatisfied

    case .smDataObjectsIncorrect:
      Iso7816Values.swSmDataObjectsIncorrect

    case .staleSecureChannel:
      Iso7816Values.swStaleSecureChannel

    case .success:
      Iso7816Values.swSuccess

    case .wrongExpectedLength(let availableLength):
      Iso7816Values.swWrongLengthPrefix | UInt16(availableLength)

    case .wrongLength:
      Iso7816Values.swWrongLength
    }
  }

  /// Classifies the two trailing response bytes.
  public init(sw1: UInt8, sw2: UInt8) {
    let value = UInt16(sw1) << Iso7816Values.byteShift | UInt16(sw2)
    if value & Iso7816Values.swFamilyMask == Iso7816Values.swResponseAvailablePrefix {
      self = .responseAvailable(count: sw2)
      return
    }
    if value & Iso7816Values.swFamilyMask == Iso7816Values.swWrongLengthPrefix {
      self = .wrongExpectedLength(availableLength: sw2)
      return
    }
    if value & Iso7816Values.swPinCounterMask == Iso7816Values.swPinCounterPrefix {
      let nibble = sw2 & Iso7816Values.lowNibbleMask
      if let remaining = RetryCount(attemptsRemaining: nibble) {
        self = .pinIncorrect(remaining: remaining)
        return
      }
    }
    self = Self.simpleClassifications[value] ?? .other(value)
  }
}
