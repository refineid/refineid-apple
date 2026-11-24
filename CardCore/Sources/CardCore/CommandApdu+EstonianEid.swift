// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Estonian eID command APDU constructors split from `CommandApdu.swift`.
extension CommandApdu {
  /// SELECT main file with no data field (`00 A4 00 0C`), as used by
  /// EstEID 2018 IAS-ECC (ID1 Developer Guide 2025 section 9).
  public static func selectMainFileNoData() -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insSelect,
        Iso7816Values.selectByFileIdP1,
        Iso7816Values.selectNoResponseP2,
      ])
    )
  }

  /// SELECT by path from the main file or application root
  /// (`00 A4 08 0C Lc <path>`), as used by EstEID 2025 for `ADF1:3411`,
  /// `ADF2:3421`, and `DFDD:5007` (ISO 7816-4 section 11.1.1; GED24035
  /// section 8.5).
  public static func selectByPath(_ path: [FileIdentifier]) -> Self {
    let pathBytes = path.flatMap(\.bytes)
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insSelect,
      Iso7816Values.selectByPathFromMfP1,
      Iso7816Values.selectNoResponseP2,
      UInt8(pathBytes.count),
    ]
    bytes.append(contentsOf: pathBytes)
    return Self(encoded: Data(bytes))
  }

  /// MSE:SET Authentication Template for EstEID 2018 ECDSA authentication
  /// (`00 22 41 A4 09 80 04 FF 20 08 00 84 01 81`, ID1 Developer Guide 2025
  /// section 9.6).
  public static func selectEstonian2018AuthenticationEnvironment() -> Self {
    let mechanism = EstonianEidValues.authMechanismReference2018
    var crdo: [UInt8] = [
      FineidValues.crdoAlgorithmReferenceTag,
      UInt8(mechanism.count),
    ]
    crdo.append(contentsOf: mechanism)
    crdo.append(contentsOf: [
      FineidValues.crdoKeyReferenceTag,
      FineidValues.crdoValueLength,
      EstonianEidValues.authKeyReference2018,
    ])
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insManageSecurityEnvironment,
      Iso7816Values.mseSetP1,
      Iso7816Values.mseAuthenticationTemplateP2,
      UInt8(crdo.count),
    ]
    bytes.append(contentsOf: crdo)
    return Self(encoded: Data(bytes))
  }

  /// MSE:SET Digital Signature Template for EstEID 2018 ECDSA qualified signing
  /// (`00 22 41 B6 09 80 04 FF 15 08 00 84 01 9F`, ID1 Developer Guide 2025
  /// section 9.5.1).
  public static func selectEstonian2018SigningEnvironment() -> Self {
    let mechanism = EstonianEidValues.signatureMechanismReference2018
    var crdo: [UInt8] = [
      FineidValues.crdoAlgorithmReferenceTag,
      UInt8(mechanism.count),
    ]
    crdo.append(contentsOf: mechanism)
    crdo.append(contentsOf: [
      FineidValues.crdoKeyReferenceTag,
      FineidValues.crdoValueLength,
      EstonianEidValues.qualifiedKeyReference2018,
    ])
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insManageSecurityEnvironment,
      Iso7816Values.mseSetP1,
      Iso7816Values.mseDigitalSignatureTemplateP2,
      UInt8(crdo.count),
    ]
    bytes.append(contentsOf: crdo)
    return Self(encoded: Data(bytes))
  }

  /// INTERNAL AUTHENTICATE over a pre-normalized P-384 digest
  /// (`00 88 00 00 <Lc> <digest> 00`, ID1 Developer Guide 2025 section 9.6).
  public static func internalAuthenticate(overDigest digest: Data) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insInternalAuthenticate,
      0,
      0,
      UInt8(digest.count),
    ]
    bytes.append(contentsOf: digest)
    bytes.append(Iso7816Values.expectedLengthMaximumEncoding)
    return Self(encoded: Data(bytes))
  }
}
