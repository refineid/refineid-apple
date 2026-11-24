// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// EstEID 2025 (Thales MultiApp v5.1, GED24035) card protocol, identity,
/// directory discovery, signing, and credential management tests.
@Suite
internal struct Estonian2025CardTests {
  private static let syntheticDocNumber = "AA0000001"
  private static let syntheticDocNumberHex = "414130303030303031"
  private static let estonianAllowance = EstonianEidValues.pinRetryLimit
  private static let p384RawSignatureLength = 96

  /// PKCS#15 private-key directory (`EF.PrKD`, FID `5034`).
  private static let privateKeyDirectoryFileHex = "5034"
  /// PKCS#15 certificate directory (`EF.CD`, FID `5037`).
  private static let certificateDirectoryFileHex = "5037"
  /// Synthetic re-keyed EstEID 2025 authentication certificate EF under `ADF1`
  /// (distinct from the initial default `EF.3411` to prove dynamic discovery).
  private static let rekeyedAuthCertificateFileHex = "3412"
  /// Synthetic re-keyed EstEID 2025 qualified-signature certificate EF under `ADF2`
  /// (distinct from the initial default `EF.3421` to prove dynamic discovery).
  private static let rekeyedSignCertificateFileHex = "3422"
  /// Synthetic re-keyed authentication private-key reference (distinct from default `01`).
  private static let rekeyedAuthKeyRef: UInt8 = 2
  /// Synthetic re-keyed qualified-signature private-key reference (distinct from default `05`).
  private static let rekeyedSignKeyRef: UInt8 = 6

  /// EF.OD pointing to EF.5034 (PrKD), EF.5037 (CD), and EF.5006 (AOD).
  private static let sampleObjectDirectory =
    "A00A300804063F005015" + privateKeyDirectoryFileHex
    + "A40A300804063F005015" + certificateDirectoryFileHex
    + "A80A300804063F0050155006"

  /// EF.CD pointing to re-keyed auth cert (`ADF1/3412`) and sign cert (`ADF2/3422`).
  private static let sampleCertificateDirectory =
    "301B30060C04417574683003040101A10C300A300804063F00ADF1" + rekeyedAuthCertificateFileHex
    + "301B30060C045369676E3003040102A10C300A300804063F00ADF2" + rekeyedSignCertificateFileHex

  /// EF.PrKD with auth key ref `02` (`sign`, bit 2 = `20`) and sign key ref `06`
  /// (`nonRepudiation`, bit 9 = `0040`).
  private static let samplePrivateKeyDirectory =
    "301430060C0441757468300A04010103020020020102"
    + "301530060C045369676E300B0401020303000040020106"

  internal static func padZero12Hex(_ digits: String) -> String {
    let raw = digits.utf8.map { String(format: "%02X", $0) }.joined()
    let padCount = max(0, Pin1.maximumDigitCount - digits.count)
    return raw + String(repeating: "00", count: padCount)
  }

  private static func fileId(_ hex: String) -> FileIdentifier {
    let bytes = Array(WireHex.data(hex))
    return FileIdentifier(value: UInt16(bytes[0]) << UInt8.bitWidth | UInt16(bytes[1]))
  }

  private static func estonian2025AodHex() -> String {
    let aodBytes = AuthenticationObjectFixture.file([
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
    return aodBytes.map { String(format: "%02X", $0) }.joined()
  }

  @Test
  internal func pkcs15DirectoryParsesAuthObjectsPathsAndKeyUsage() {
    let locations = Pkcs15Directory.locations(
      fromObjectDirectory: WireHex.data(Self.sampleObjectDirectory)
    )
    #expect(locations.authObjects == .estonian2025Aod)
    #expect(locations.certificates == Self.fileId(Self.certificateDirectoryFileHex))
    #expect(locations.privateKeys == Self.fileId(Self.privateKeyDirectoryFileHex))

    let certs = Pkcs15Directory.certificates(
      fromDirectory: WireHex.data(Self.sampleCertificateDirectory)
    )
    #expect(certs.count == 2)
    #expect(
      certs[0].path == [.estonianAwpDirectory, Self.fileId(Self.rekeyedAuthCertificateFileHex)]
    )
    #expect(
      certs[1].path == [.estonianQscdDirectory, Self.fileId(Self.rekeyedSignCertificateFileHex)]
    )

    let keys = Pkcs15Directory.privateKeys(
      fromDirectory: WireHex.data(Self.samplePrivateKeyDirectory)
    )
    #expect(keys.count == 2)
    #expect(keys[0].usage == .sign)
    #expect(keys[0].keyReference == Self.rekeyedAuthKeyRef)
    #expect(keys[1].usage == .nonRepudiation)
    #expect(keys[1].keyReference == Self.rekeyedSignKeyRef)
  }

  @Test
  internal func pin2ProbeFirstStillResolvesEstonian2025ViaPin1() throws {
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "6A88"),
      ("0020008100", "63C3"),
      ("0020008200", "63C3"),
    ])
    let operations = CardOperations(channel: channel)
    let pin2Outcome = try operations.probeRetryCounter(role: .pin2)
    #expect(pin2Outcome == .remaining(three))
    #expect(operations.resolvedNumbering == .estonian2025)
    #expect(operations.pristineRetryAllowance == Self.estonianAllowance)
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025IdentitySerialsSeparateChipSerialAndDocumentNumber() throws {
    // 8-byte binary chip serial rendered as 16 uppercase hex characters in EF.TokenInfo.
    let tokenInfo = "300D02010004080123456789ABCDEF"
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "6A88"),
      ("0020008100", "63C3"),
      ("00A4020C025032", "9000"),
      ("00B0000080", tokenInfo + "9000"),
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4080C04DFDD5007", "9000"),
      ("00B000000A", "6282"),
      ("00B0000000", Self.syntheticDocNumberHex + "9000"),
      ("00A4040C0CA000000063504B43532D3135", "9000"),
    ])
    let serials = try CardOperations(channel: channel).readCardIdentitySerials()
    #expect(serials.chipSerial.value == "0123456789ABCDEF")
    #expect(serials.printedSerial.value == Self.syntheticDocNumber)
    #expect(
      TokenInstanceID(printedSerial: serials.printedSerial).value == "refineid-card-aa0000001")
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025DiscoversRekeyedCertificatesAndPinLengths() throws {
    let authDer = "3004AABBCCDD"
    let signDer = "3004EEFF0011"
    let channel = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4020C025031", "9000"),
      ("00B0000080", Self.sampleObjectDirectory + "9000"),
      ("00A4020C025037", "9000"),
      ("00B0000080", Self.sampleCertificateDirectory + "9000"),
      ("00A4020C025034", "9000"),
      ("00B0000080", Self.samplePrivateKeyDirectory + "9000"),
      ("00A4080C04ADF1" + Self.rekeyedAuthCertificateFileHex, "9000"),
      ("00B0000080", authDer + "9000"),
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4080C04ADF2" + Self.rekeyedSignCertificateFileHex, "9000"),
      ("00B0000080", signDer + "9000"),
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4040C0CA000000063504B43532D3135", "9000"),
      ("00A4020C025006", "9000"),
      ("00B0000080", Self.estonian2025AodHex() + "9000"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    #expect(try operations.readCertificate(.authentication) == WireHex.data(authDer))
    #expect(try operations.readCertificate(.qualifiedSignature) == WireHex.data(signDer))
    #expect(throws: CardOperationError.selectRejected(.fileNotFound)) {
      _ = try operations.readCertificate(.issuing)
    }

    let lengths = try operations.readCardPinLengths()
    #expect(
      lengths.pin1.accepted
        == PasswordLengthRange(minimum: Pin1.minimumDigitCount, maximum: Pin1.maximumDigitCount)
    )
    #expect(
      lengths.pin2.accepted
        == PasswordLengthRange(
          minimum: EstonianEidValues.pin2MinimumDigitCount,
          maximum: Pin2.maximumDigitCount
        )
    )
    #expect(
      lengths.puk.accepted
        == PasswordLengthRange(minimum: Puk.minimumDigitCount, maximum: Puk.maximumDigitCount)
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025SignsWithDiscoveredRekeyedKeyReferences() throws {
    let digestHex = String(repeating: "42", count: EstonianEidValues.p384DigestLength)
    let signatureHex = String(repeating: "7A", count: Self.p384RawSignatureLength)
    let channel = ScriptedChannel([
      ("00A4020C025031", "9000"),
      ("00B0000080", Self.sampleObjectDirectory + "9000"),
      ("00A4020C025037", "9000"),
      ("00B0000080", Self.sampleCertificateDirectory + "9000"),
      ("00A4020C025034", "9000"),
      ("00B0000080", Self.samplePrivateKeyDirectory + "9000"),
      ("002000810C" + Self.padZero12Hex("1234"), "9000"),
      ("002241B606800154840102", "9000"),
      ("002A90A0329030" + digestHex, "9000"),
      ("002A9E9A60", signatureHex + "9000"),
      ("002000820C" + Self.padZero12Hex("12345"), "9000"),
      ("002241B606800154840106", "9000"),
      ("002A90A0329030" + digestHex, "9000"),
      ("002A9E9A60", signatureHex + "9000"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    guard let pin1 = Pin1(digits: "1234"), let pin2 = Pin2(digits: "12345") else {
      Issue.record("synthetic PIN failed to construct")
      return
    }
    try operations.verifyPin1(pin1.consumeForSingleTransmission())
    let authSig = try operations.computeAuthenticationSignature(
      overDigest: WireHex.data(digestHex),
      algorithm: SigningAlgorithm(hash: .sha384, scheme: .ecdsa),
      expectedSignatureLength: ExpectedResponseLength(count: Self.p384RawSignatureLength)
    )
    #expect(authSig == WireHex.data(signatureHex))

    try operations.verifyPin2(pin2.consumeForSingleTransmission())
    let signSig = try operations.computeQualifiedSignature(
      overDigest: WireHex.data(digestHex),
      algorithm: SigningAlgorithm(hash: .sha384, scheme: .ecdsa),
      expectedSignatureLength: ExpectedResponseLength(count: Self.p384RawSignatureLength)
    )
    #expect(signSig == WireHex.data(signatureHex))
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025ProbeCredentialsAndActivationMatchThreeTryAllowance() throws {
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "6A88"),
      ("0020008100", "63C3"),
      ("0020008200", "63C3"),
      ("00CB00FF05A00383018300", "DF2104030A0AFF9000"),
    ])
    let operations = CardOperations(channel: channel)
    let report = try operations.probeCredentials()
    #expect(report.pin1 == .remaining(three))
    #expect(report.pin2 == .remaining(three))
    #expect(report.puk == .remaining(three))
    #expect(report.pristineAllowance == Self.estonianAllowance)
    #expect(operations.activationClassification() == .estonian)
    #expect(
      operations.activationNeeds(scheme: .presetActivationPin)
        == CardActivationNeeds(pin1: false, pin2: false)
    )
    #expect(channel.isExhausted)
  }
}
