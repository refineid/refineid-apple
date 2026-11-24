// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The dedicated home for Estonian eID wire values.
///
/// Sources:
/// - EstEID 2025 (Thales MultiApp v5.1): GED24035_015 TDC EstEID Developer Guide v1.33.
/// - EstEID 2018 / 2018 v2 (IDEMIA Cosmo v8.1, v8.2, Cosmo X): RIA ID1 Developer Guide 2025.
///
/// No raw hex literal may appear outside `Values/` (`.swiftlint.yml` `unexplained_hex`).
internal enum EstonianEidValues {
  /// EstEID 2018 (Cosmo v8.1 / v8.2) IAS-ECC root application AID.
  internal static let legacyRootAidHexDigits = "A000000077010800070000FE00000100"

  /// EstEID 2018 v2 (Cosmo X) IAS-ECC root application AID (ID1 Developer Guide 2025 section 6).
  internal static let legacyCosmoXRootAidHexDigits = "A000000077030C60000000FE00000500"

  /// EstEID 2025 local PIN 1 reference (GED24035 section 5.3.3).
  internal static let pin1Reference2025: UInt8 = 0x81

  /// EstEID 2025 local PIN 2 reference (GED24035 section 5.3.3).
  internal static let pin2Reference2025: UInt8 = 0x82

  /// EstEID 2025 local PUK reference (GED24035 section 5.3.3).
  internal static let pukReference2025: UInt8 = 0x83

  /// EstEID 2018 global PIN 1 reference under MF (ID1 Developer Guide 2025 section 6.5).
  internal static let pin1Reference2018: UInt8 = 0x01

  /// EstEID 2018 local PIN 2 reference under ADF2 (ID1 Developer Guide 2025 section 8.1).
  internal static let pin2Reference2018: UInt8 = 0x85

  /// EstEID 2018 global PUK reference under MF (ID1 Developer Guide 2025 section 6.6).
  internal static let pukReference2018: UInt8 = 0x02

  /// Padding byte for EstEID 2018 12-byte PIN and PUK blocks (ID1 Developer Guide 2025 section 9.3.2).
  internal static let legacyPinPadByte: UInt8 = 0xFF

  /// Full retry allowance for Estonian eID credentials (PIN 1, PIN 2, PUK).
  internal static let pinRetryLimit: UInt8 = 3

  /// Shortest PIN 2 on Estonian eID cards (GED24035 section 5.3.3; ID1 Developer Guide 2025).
  internal static let pin2MinimumDigitCount = 5

  /// DF.AWP (`ADF1`): authentication application directory on EstEID 2018 and EstEID 2025.
  internal static let fileIdAwpDirectory: UInt16 = 0xADF1

  /// DF.QSCD (`ADF2`): qualified signature application directory on EstEID 2018 and EstEID 2025.
  internal static let fileIdQscdDirectory: UInt16 = 0xADF2

  /// DF.DocumentData (`DFDD`): personal-data directory inside the EstEID 2025 eID application.
  internal static let fileIdDocumentDataDirectory: UInt16 = 0xDFDD

  /// DF.5000: personal-data directory under MF on EstEID 2018.
  internal static let fileIdLegacyPersonalDataDirectory: UInt16 = 0x5000

  /// EF.5007: PD7 Document number (`XX9999999`), plain ASCII under DF.DD (2025) or DF.5000 (2018).
  internal static let fileIdDocumentNumberPlain: UInt16 = 0x5007

  /// EF.D003: DER-TLV document number under MF on EstEID 2018 (ID1 Developer Guide 2025 section 6.1).
  internal static let fileIdDocumentNumberTlv: UInt16 = 0xD003

  /// EF.5006: EstEID 2025 default EF.AOD under the eID application (GED24035 section 5.3.3).
  internal static let fileIdEstonian2025Aod: UInt16 = 0x5006

  /// EF.3411: EstEID 2025 default authentication certificate under ADF1 (GED24035 section 5.3.5).
  internal static let fileIdEstonian2025AuthCertificate: UInt16 = 0x3411

  /// EF.3421: EstEID 2025 default signature certificate under ADF2 (GED24035 section 5.3.5).
  internal static let fileIdEstonian2025SignatureCertificate: UInt16 = 0x3421

  /// EF.3401: EstEID 2018 primary authentication certificate under ADF1 (ID1 Developer Guide 2025 section 7.10).
  internal static let fileIdEstonian2018AuthCertificate: UInt16 = 0x3401

  /// EF.3402: EstEID 2018 re-keyed authentication certificate under ADF1.
  internal static let fileIdEstonian2018SecondAuthCertificate: UInt16 = 0x3402

  /// EF.341F: EstEID 2018 primary signature certificate under ADF2 (ID1 Developer Guide 2025 section 8.11).
  internal static let fileIdEstonian2018SignatureCertificate: UInt16 = 0x341F

  /// EF.341E: EstEID 2018 re-keyed signature certificate under ADF2.
  internal static let fileIdEstonian2018AltSignCertificate: UInt16 = 0x341E

  /// Default EstEID 2025 authentication private-key reference before re-key (GED24035 section 5.3.4).
  internal static let defaultAuthKeyReference2025: UInt8 = 0x01

  /// Default EstEID 2025 qualified-signature private-key reference before re-key (GED24035 section 5.3.4).
  internal static let defaultQualifiedKeyReference2025: UInt8 = 0x05

  /// EstEID 2018 authentication private-key reference in ADF1 (ID1 Developer Guide 2025 section 9.6).
  internal static let authKeyReference2018: UInt8 = 0x81

  /// EstEID 2018 qualified-signature private-key reference in ADF2 (ID1 Developer Guide 2025 section 9.5.1).
  internal static let qualifiedKeyReference2018: UInt8 = 0x9F

  /// EstEID 2018 MSE:SET AT cryptographic mechanism reference for ECDSA authentication (`FF 20 08 00`).
  internal static let authMechanismReference2018: [UInt8] = [0xFF, 0x20, 0x08, 0x00]

  /// EstEID 2018 MSE:SET DST cryptographic mechanism reference for ECDSA signature (`FF 15 08 00`).
  internal static let signatureMechanismReference2018: [UInt8] = [0xFF, 0x15, 0x08, 0x00]

  /// Fixed P-384 digest length expected by EstEID 2018 INTERNAL AUTHENTICATE and PSO:CDS (`0x30` = 48 bytes).
  internal static let p384DigestLength = 48

  /// DER tag of EF.D003 on Cosmo v8.1 / v8.2: universal OCTET STRING.
  internal static let documentNumberTagOctetString: UInt8 = 0x04

  /// DER tag of EF.D003 on Cosmo X: `[APPLICATION 26]` primitive (ID1 Developer Guide 2025 section 6.1).
  internal static let documentNumberTagApplication26: UInt8 = 0x5A

  /// Highest single-byte short-form DER length (ITU-T X.690 section 8.1.3).
  internal static let shortFormDerLengthMax: UInt8 = 0x7F

  /// Characters in the Estonian printed document number `XX9999999`.
  internal static let documentNumberCharacterCount = 9

  /// Leading uppercase ASCII letters in `XX9999999`.
  internal static let documentNumberLetterPrefixCount = 2

  /// Read cap for plain-ASCII EF.5007: one byte past a valid number so oversized files are rejected.
  internal static let documentNumberProbeCap = 10

  /// Historical-bytes marker for EstEID 2018 Cosmo v8 (`23 3F 53 65 49 44`, country Estonia + "SeID").
  internal static let legacyCosmoV8Marker: [UInt8] = [0x23, 0x3F, 0x53, 0x65, 0x49, 0x44]

  /// Historical-bytes marker for EstEID 2018 Cosmo X (`23 3F 54 65 49 44 32`, country Estonia + "TeID2").
  internal static let legacyCosmoXMarker: [UInt8] = [0x23, 0x3F, 0x54, 0x65, 0x49, 0x44, 0x32]

  /// The VERIFY P2 reference for a role on EstEID 2025.
  internal static func reference2025(for role: CredentialRole) -> UInt8 {
    switch role {
    case .pin1:
      pin1Reference2025

    case .pin2:
      pin2Reference2025

    case .puk:
      pukReference2025
    }
  }

  /// The VERIFY P2 reference for a role on EstEID 2018.
  internal static func reference2018(for role: CredentialRole) -> UInt8 {
    switch role {
    case .pin1:
      pin1Reference2018

    case .pin2:
      pin2Reference2018

    case .puk:
      pukReference2018
    }
  }
}
