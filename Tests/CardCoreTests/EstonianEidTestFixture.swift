// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Typed builders for Estonian eID card fixtures, DER directories, and APDU
/// expectations assembled exclusively from named constants and domain types.
internal enum EstonianEidTestFixture {
  /// Synthetic nine-character Estonian document numbers (`XX9999999`).
  internal static let syntheticDocNumber2025 = "AA0000001"
  internal static let syntheticDocNumber2018 = "BB0000002"
  internal static let syntheticCan = "123456"

  /// Synthetic PIN / PUK digit strings used across unit tests.
  internal static let samplePin1 = "1234"
  internal static let sampleNewPin1 = "5678"
  internal static let sampleResetPin1 = "4321"
  internal static let samplePin2 = "12345"
  internal static let sampleNewPin2 = "54321"
  internal static let sampleResetPin2 = "98765"
  internal static let samplePuk = "12345678"

  /// Synthetic PKCS#15 object identifiers for paired auth / sign entries.
  internal static let authObjectId: UInt8 = 1
  internal static let signObjectId: UInt8 = 2

  /// Synthetic re-keyed EstEID 2025 private-key references (distinct from
  /// initial defaults to prove live `EF.PrKD` discovery).
  internal static let rekeyedAuthKeyRef: UInt8 = EstonianEidValues.defaultAuthKeyReference2025 + 1
  internal static let rekeyedSignKeyRef: UInt8 =
    EstonianEidValues.defaultQualifiedKeyReference2025 + 1

  /// Synthetic re-keyed EstEID 2025 certificate EF identifiers (distinct from
  /// initial defaults to prove live `EF.CD` discovery).
  internal static let rekeyedAuthCertFile = FileIdentifier(
    value: EstonianEidValues.fileIdEstonian2025AuthCertificate + 1
  )
  internal static let rekeyedSignCertFile = FileIdentifier(
    value: EstonianEidValues.fileIdEstonian2025SignatureCertificate + 1
  )

  /// Offsets from `EF.OD` (`5031`) to `EF.PrKD` (`5034`) and `EF.CD` (`5037`).
  private static let privateKeyDirectoryOffset: UInt16 = 3
  private static let certificateDirectoryOffset: UInt16 = 6

  /// Synthetic PKCS#15 directory file identifiers derived relative to `EF.OD`.
  internal static let privateKeyDirectoryFile = FileIdentifier(
    value: FineidValues.fileIdObjectDirectory + privateKeyDirectoryOffset
  )
  internal static let certificateDirectoryFile = FileIdentifier(
    value: FineidValues.fileIdObjectDirectory + certificateDirectoryOffset
  )

  /// Standard digest lengths and raw ECDSA P-384 signature width (`r || s`).
  internal static let sha256DigestLength = 32
  internal static let sha512DigestLength = 64
  private static let ecdsaCoordinateCount = 2
  internal static let p384RawSignatureLength =
    EstonianEidValues.p384DigestLength * ecdsaCoordinateCount

  /// Synthetic valid-DER payloads built from ASCII strings.
  internal static let syntheticAuthCertDer = derDocument("synthetic-estonian-auth-cert")
  internal static let syntheticSignCertDer = derDocument("synthetic-estonian-sign-cert")
  internal static let syntheticSignatureBytes = Data(
    repeating: UInt8(ascii: "S"),
    count: p384RawSignatureLength
  )

  /// Common encoded SELECT commands.
  internal static let selectApp = CommandApdu.selectApplication(.fineidApplication).encoded
  internal static let selectRoot2018 = CommandApdu.selectMainFileNoData().encoded
  internal static let selectAwp = selectChild(.estonianAwpDirectory)
  internal static let selectQscd = selectChild(.estonianQscdDirectory)

  internal static func selectEf(_ file: FileIdentifier) -> Data {
    CommandApdu.selectElementaryFile(file).encoded
  }

  internal static func selectByFid(_ file: FileIdentifier) -> Data {
    CommandApdu.selectFile(file, selectionP1: Iso7816Values.selectByFileIdP1).encoded
  }

  internal static func selectChild(_ directory: FileIdentifier) -> Data {
    CommandApdu.selectFile(directory, selectionP1: Iso7816Values.selectChildDfP1).encoded
  }

  internal static func status(_ word: StatusWord) -> Data {
    let encoded = word.encoded
    return Data([
      UInt8(encoded >> Iso7816Values.byteShift),
      UInt8(encoded & Iso7816Values.lowByteMask),
    ])
  }

  internal static func response(_ payload: Data, status word: StatusWord) -> Data {
    payload + status(word)
  }

  internal static func responseApdu(_ payload: Data, status word: StatusWord) throws -> ResponseApdu
  {
    try #require(ResponseApdu(raw: response(payload, status: word)))
  }

  internal static func remaining(_ attempts: UInt8) throws -> StatusWord {
    .pinIncorrect(remaining: try #require(RetryCount(attemptsRemaining: attempts)))
  }

  internal static func readBinary(offset: UInt16, count: Int) throws -> Data {
    let readOffset = try #require(ReadOffset(value: offset))
    let expected = try #require(ExpectedResponseLength(count: count))
    return CommandApdu.readBinary(offset: readOffset, expectedLength: expected).encoded
  }

  internal static func derDocument(_ ascii: String) -> Data {
    DerEncoder.sequence([DerEncoder.octetString(Data(ascii.utf8))])
  }

  internal static func tokenInfo(serialBytes: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.integer(.zero),
      DerEncoder.octetString(serialBytes),
    ])
  }

  internal static func pinAttributesResponse(attemptsRemaining: UInt8) -> Data {
    Data([
      FineidValues.pinAttributesTagHigh,
      FineidValues.pinAttributesTagLow,
      FineidValues.pinAttributesLength,
      attemptsRemaining,
      FineidValues.usageUnlimited,
      FineidValues.unblockingUnlimited,
      FineidValues.usageUnlimited,
    ])
  }

  internal static func objectDirectory() -> Data {
    let entry: (UInt8, FileIdentifier) -> Data = { tag, file in
      let pathBytes = Data(FileIdentifier.mainFile.bytes + file.bytes)
      return DerEncoder.tlv(tag, DerEncoder.sequence([DerEncoder.octetString(pathBytes)]))
    }
    return entry(Pkcs15Values.privateKeysTag, privateKeyDirectoryFile)
      + entry(Pkcs15Values.certificatesTag, certificateDirectoryFile)
      + entry(Pkcs15Values.authObjectsTag, .estonian2025Aod)
  }

  internal static func certificateDirectory() -> Data {
    let certEntry: (String, UInt8, [FileIdentifier]) -> Data = { label, objectId, path in
      let pathBytes = Data(([.mainFile] + path).flatMap(\.bytes))
      let common = DerEncoder.sequence([
        DerEncoder.tlv(Pkcs15Values.utf8StringTag, Data(label.utf8))
      ])
      let classAttrs = DerEncoder.sequence([DerEncoder.octetString(Data([objectId]))])
      let typeAttrs = DerEncoder.tlv(
        Pkcs15Values.typeAttributesTag,
        DerEncoder.sequence([DerEncoder.sequence([DerEncoder.octetString(pathBytes)])])
      )
      return DerEncoder.sequence([common, classAttrs, typeAttrs])
    }
    return certEntry("Auth", authObjectId, [.estonianAwpDirectory, rekeyedAuthCertFile])
      + certEntry("Sign", signObjectId, [.estonianQscdDirectory, rekeyedSignCertFile])
  }

  internal static func privateKeyDirectory() -> Data {
    let keyEntry: (String, UInt8, [UInt8], UInt8) -> Data = { label, objectId, usageBits, ref in
      let common = DerEncoder.sequence([
        DerEncoder.tlv(Pkcs15Values.utf8StringTag, Data(label.utf8))
      ])
      let classAttrs = DerEncoder.sequence([
        DerEncoder.octetString(Data([objectId])),
        DerEncoder.tlv(DerValues.tagBitString, Data(usageBits)),
        DerEncoder.integer(Int(ref)),
      ])
      return DerEncoder.sequence([common, classAttrs])
    }
    let signUsage = [DerValues.bitStringNoUnusedBits, Pkcs15Values.keyUsageSignBitMask]
    let nonRepUsage = [
      DerValues.bitStringNoUnusedBits,
      .zero,
      Pkcs15Values.keyUsageNonRepudiationBitMask,
    ]
    return keyEntry("Auth", authObjectId, signUsage, rekeyedAuthKeyRef)
      + keyEntry("Sign", signObjectId, nonRepUsage, rekeyedSignKeyRef)
  }

  internal static func estonian2025Aod() -> Data {
    AuthenticationObjectFixture.file([
      AuthenticationObjectFixture.citizen(
        reference: EstonianEidValues.pin1Reference2025,
        minimum: Pin1.minimumDigitCount
      ).encoded,
      AuthenticationObjectFixture.citizen(
        reference: EstonianEidValues.pin2Reference2025,
        minimum: EstonianEidValues.pin2MinimumDigitCount
      ).encoded,
      AuthenticationObjectFixture.citizen(
        reference: EstonianEidValues.pukReference2025,
        minimum: Puk.minimumDigitCount
      ).encoded,
    ])
  }

  internal static func paddedPinBlock(_ digits: String, padByte: UInt8) -> Data {
    let raw = Data(digits.utf8)
    let padCount = max(0, FineidValues.pinStoredLength - raw.count)
    return raw + Data(repeating: padByte, count: padCount)
  }

  internal static func atr(historicalBytes: [UInt8]) -> Data {
    let directConventionTs = UInt8(ascii: ";")
    let t0Byte = UInt8(historicalBytes.count) & AnswerToResetValues.historicalCountMask
    return Data([directConventionTs, t0Byte] + historicalBytes)
  }
}
