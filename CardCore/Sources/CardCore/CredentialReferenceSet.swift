// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Which credential reference numbering the card in session uses.
///
/// - FINEID citizen cards (FINEID S1 v4.2 section 3.5.2): global PIN 1 `11`,
///   local PIN 2 `82`, PUK `83`, zero-padded to 12 bytes, 5-try allowance.
/// - FINEID organization cards (FINEID S4-2 v4.0 section 4.2): PIN AUTH `03`,
///   PIN SIG `04`, PIN PUK `12`, bare digits (no padding), 5-try allowance.
/// - EstEID 2025 (Thales MultiApp v5.1, GED24035 section 5.3.3): local PIN 1
///   `81`, local PIN 2 `82`, local PUK `83`, zero-padded to 12 bytes, 3-try
///   allowance.
/// - EstEID 2018 / 2018 v2 (IDEMIA Cosmo v8 / Cosmo X, ID1 Developer Guide
///   2025): global PIN 1 `01`, local PIN 2 `85` under ADF2, global PUK `02`,
///   FF-padded to 12 bytes, 3-try allowance.
public enum CredentialReferenceSet: String, Codable, Equatable, Sendable {
  /// FINEID S1 v4.2 section 3.5.2 numbering, the Finnish citizen cards.
  case citizen = "citizen"

  /// EstEID 2018 / 2018 v2 (IDEMIA IAS-ECC) numbering.
  case estonian2018 = "estonian2018"

  /// EstEID 2025 (Thales MultiApp v5.1) numbering.
  case estonian2025 = "estonian2025"

  /// FINEID S4-2 v4.0 section 4.2 security-data-object numbering, the
  /// Finnish organization cards.
  case organization = "organization"

  /// Whether this card belongs to an Estonian eID generation.
  public var isEstonian: Bool {
    self == .estonian2018 || self == .estonian2025
  }

  /// Full retry allowance of an untouched credential on this card.
  public var pristineRetryAllowance: UInt8 {
    switch self {
    case .citizen, .organization:
      RetryCount.pristineAllowance

    case .estonian2018, .estonian2025:
      EstonianEidValues.pinRetryLimit
    }
  }

  /// Byte used to right-pad 12-byte credential blocks, or nil for cards that
  /// take bare unpadded digits.
  internal var pinPadByte: UInt8? {
    switch self {
    case .citizen, .estonian2025:
      FineidValues.pinPadByte

    case .estonian2018:
      EstonianEidValues.legacyPinPadByte

    case .organization:
      nil
    }
  }

  /// Fallback minimum digit count for PIN 2 when EF.AOD does not list one.
  internal var fallbackPin2MinimumDigitCount: Int {
    switch self {
    case .citizen, .organization:
      CardPinLengths.fineidPin2MinimumDigitCount

    case .estonian2018, .estonian2025:
      EstonianEidValues.pin2MinimumDigitCount
    }
  }

  /// The VERIFY P2 reference for a role under this numbering.
  internal func reference(for role: CredentialRole) -> UInt8 {
    switch self {
    case .citizen:
      FineidValues.reference(for: role)

    case .estonian2018:
      EstonianEidValues.reference2018(for: role)

    case .estonian2025:
      EstonianEidValues.reference2025(for: role)

    case .organization:
      FineidValues.organizationReference(for: role)
    }
  }
}
