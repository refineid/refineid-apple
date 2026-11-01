// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A two-byte ISO 7816-4 file identifier.
public struct FileIdentifier: Equatable, Sendable {
  /// EF.ODF: the PKCS#15 object directory under the eID application.
  public static let objectDirectory = Self(
    value: FineidValues.fileIdObjectDirectory
  )

  /// EF.TokenInfo: the PKCS#15 token information file, source of the
  /// full hardware serial.
  public static let tokenInfo = Self(value: FineidValues.fileIdTokenInfo)

  /// EF.AOD: the PKCS#15 authentication object directory, source of the
  /// card's PIN and PUK lengths.
  public static let authenticationObjectDirectory = Self(
    value: FineidValues.fileIdAuthenticationObjectDirectory
  )

  /// The ISO 7816-4 main file (MF, FID 3F00).
  public static let mainFile = Self(value: FineidValues.fileIdMainFile)

  /// EF.COM: the travel-document application's inventory of the
  /// data groups this card carries.
  public static let commonData = Self(value: FineidValues.fileIdCommonData)

  /// EF.DG7: the holder's handwritten signature.
  public static let displayedSignature = Self(
    value: FineidValues.fileIdDisplayedSignature
  )

  /// EF.CardAccess: the SecurityInfos readable before PACE.
  public static let cardAccess = Self(value: FineidValues.fileIdCardAccess)

  /// EF.4331: the authentication certificate leaf.
  public static let authCertificate = Self(
    value: FineidValues.fileIdAuthCertificate
  )

  /// EF.4332: the qualified-signature certificate leaf.
  public static let signatureCertificate = Self(
    value: FineidValues.fileIdSignatureCertificate
  )

  /// EF.4333: the second authentication certificate leaf, under the
  /// PKCS#15 application.
  public static let secondAuthCertificate = Self(
    value: FineidValues.fileIdSecondAuthCertificate
  )

  /// EF.4335: the second qualified-signature certificate leaf.
  public static let secondSignatureCertificate = Self(
    value: FineidValues.fileIdSecondSignatureCertificate
  )

  /// EF.4334: the on-card issuing root CA.
  public static let rootCertificate = Self(
    value: FineidValues.fileIdRootCertificate
  )

  /// EF.4336: the on-card issuing intermediate CA.
  public static let issuingCertificate = Self(
    value: FineidValues.fileIdIssuingCertificate
  )

  /// EF.4333: the organization card's on-card issuing intermediate CA.
  public static let organizationIssuingCertificate = Self(
    value: FineidValues.fileIdOrganizationIssuingCertificate
  )

  /// DF.ESIGN: the organization card's signature directory.
  public static let esignDirectory = Self(
    value: FineidValues.fileIdEsignDirectory
  )

  /// The identifier as a 16-bit value.
  public let value: UInt16

  /// The two wire bytes, big-endian.
  internal var bytes: [UInt8] {
    [
      UInt8(value >> Iso7816Values.byteShift),
      UInt8(value & Iso7816Values.lowByteMask),
    ]
  }

  /// Any two-byte value is a structurally valid identifier; whether the
  /// file exists is the card's answer, not the type's.
  public init(value: UInt16) {
    self.value = value
  }
}
