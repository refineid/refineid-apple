// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// EstEID 2018 / 2018 v2 (IDEMIA Cosmo v8 / Cosmo X, ID1 Developer Guide 2025)
/// application selection, certificate reads, two-step unblocks, P-384 signing,
/// and Estonian X.509 DistinguishedName tests.
@Suite
internal struct Estonian2018CardTests {
  private static let syntheticDocNumber = "BB0000002"
  private static let syntheticDocNumberHex = "424230303030303032"
  private static let estonianAllowance = EstonianEidValues.pinRetryLimit
  private static let p384DigestLength = EstonianEidValues.p384DigestLength
  private static let sha256DigestLength = 32
  private static let sha512DigestLength = 64
  private static let p384RawSignatureLength = 96

  private static func padFF12Hex(_ digits: String) -> String {
    let raw = digits.utf8.map { String(format: "%02X", $0) }.joined()
    let padCount = max(0, Pin1.maximumDigitCount - digits.count)
    return raw + String(repeating: "FF", count: padCount)
  }

  @Test
  internal func applicationSelectFallsBackToCosmoV8AndCosmoX() throws {
    let cosmoV8 = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "6A82"),
      ("00A4040C10A000000077010800070000FE00000100", "9000"),
    ])
    let opsV8 = CardOperations(channel: cosmoV8)
    try opsV8.selectCardApplication()
    #expect(opsV8.resolvedNumbering == .estonian2018)
    #expect(opsV8.pristineRetryAllowance == Self.estonianAllowance)
    #expect(cosmoV8.isExhausted)

    let cosmoX = ScriptedChannel([
      ("00A4040C0CA000000063504B43532D3135", "6A82"),
      ("00A4040C10A000000077010800070000FE00000100", "6A82"),
      ("00A4040C10A000000077030C60000000FE00000500", "9000"),
    ])
    let opsX = CardOperations(channel: cosmoX)
    try opsX.selectCardApplication()
    #expect(opsX.resolvedNumbering == .estonian2018)
    #expect(cosmoX.isExhausted)
  }

  @Test
  internal func estonian2018CertificateReadsAndRekeyFallbacks() throws {
    let authDer = "300411223344"
    let signDer = "300455667788"
    let channel = ScriptedChannel([
      ("00A4000C", "9000"),
      ("00A4010C02ADF1", "9000"),
      ("00A4020C023401", "6A82"),
      ("00A4000C023401", "6A82"),
      ("00A4000C", "9000"),
      ("00A4010C02ADF1", "9000"),
      ("00A4020C023402", "9000"),
      ("00B0000080", authDer + "9000"),
      ("00A4000C", "9000"),
      ("00A4010C02ADF2", "9000"),
      ("00A4020C02341F", "6A82"),
      ("00A4000C02341F", "6A82"),
      ("00A4000C", "9000"),
      ("00A4010C02ADF2", "9000"),
      ("00A4020C02341E", "9000"),
      ("00B0000080", signDer + "9000"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    #expect(try operations.readCertificate(.authentication) == WireHex.data(authDer))
    #expect(try operations.readCertificate(.qualifiedSignature) == WireHex.data(signDer))
    #expect(throws: CardOperationError.selectRejected(.fileNotFound)) {
      _ = try operations.readCertificate(.issuing)
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2018DocumentNumberReadsD003TlvAndFallsBackTo5007() throws {
    let d003Channel = ScriptedChannel([
      ("00A4000C", "9000"),
      ("00A4020C02D003", "9000"),
      ("00B0000080", "5A09" + Self.syntheticDocNumberHex + "9000"),
    ])
    let serials = try CardOperations(
      channel: d003Channel,
      numbering: .estonian2018
    ).readCardIdentitySerials()
    #expect(serials.chipSerial.value == Self.syntheticDocNumber)
    #expect(serials.printedSerial.value == Self.syntheticDocNumber)
    #expect(d003Channel.isExhausted)

    let fallbackChannel = ScriptedChannel([
      ("00A4000C", "9000"),
      ("00A4020C02D003", "6A82"),
      ("00A4000C02D003", "6A82"),
      ("00A4000C", "9000"),
      ("00A4010C025000", "9000"),
      ("00A4020C025007", "9000"),
      ("00B000000A", Self.syntheticDocNumberHex + "9000"),
    ])
    let fallbackDoc = try CardOperations(
      channel: fallbackChannel,
      numbering: .estonian2018
    ).readEstonian2018DocumentNumber()
    #expect(fallbackDoc.value == Self.syntheticDocNumber)
    #expect(fallbackChannel.isExhausted)
  }

  @Test
  internal func estonian2018ProbesCountersAndPinLengths() throws {
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let channel = ScriptedChannel([
      ("00A4000C", "9000"),
      ("00200001", "63C3"),
      ("00A4000C", "9000"),
      ("00A4010C02ADF2", "9000"),
      ("00200085", "63C3"),
      ("00A4000C", "9000"),
      ("00200002", "63C3"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
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
  internal func estonian2018ChangesPinsAndRunsTwoStepUnblocks() throws {
    let lengths = CardPinLengths.notListed(numbering: .estonian2018)
    let channel = ScriptedChannel([
      ("00A4000C", "9000"),
      ("0024000118" + Self.padFF12Hex("1234") + Self.padFF12Hex("5678"), "9000"),
      ("00A4000C", "9000"),
      ("00A4010C02ADF2", "9000"),
      ("0024008518" + Self.padFF12Hex("12345") + Self.padFF12Hex("54321"), "9000"),
      ("00A4000C", "9000"),
      ("002000020C" + Self.padFF12Hex("12345678"), "9000"),
      ("002C02010C" + Self.padFF12Hex("4321"), "9000"),
      ("00A4000C", "9000"),
      ("002000020C" + Self.padFF12Hex("12345678"), "9000"),
      ("00A4010C02ADF2", "9000"),
      ("002C02850C" + Self.padFF12Hex("98765"), "9000"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    guard
      let oldPin1 = Pin1(digits: "1234"),
      let newPin1 = Pin1(digits: "5678"),
      let oldPin2 = Pin2(digits: "12345"),
      let newPin2 = Pin2(digits: "54321"),
      let puk1 = Puk(digits: "12345678"),
      let resetPin1 = Pin1(digits: "4321"),
      let puk2 = Puk(digits: "12345678"),
      let resetPin2 = Pin2(digits: "98765")
    else {
      Issue.record("synthetic credentials failed to construct")
      return
    }
    try operations.changePin1(
      current: oldPin1.consumeForSingleTransmission(),
      new: newPin1.consumeForSingleTransmission(),
      lengths: lengths
    )
    try operations.changePin2(
      current: oldPin2.consumeForSingleTransmission(),
      new: newPin2.consumeForSingleTransmission(),
      lengths: lengths
    )
    try operations.unblockPin1(
      puk: puk1.consumeForSingleTransmission(),
      new: resetPin1.consumeForSingleTransmission(),
      lengths: lengths
    )
    try operations.unblockPin2(
      puk: puk2.consumeForSingleTransmission(),
      new: resetPin2.consumeForSingleTransmission(),
      lengths: lengths
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2018SigningNormalizesDigestAndUsesInternalAuthAndPsoCds() throws {
    let sha256 = WireHex.data(String(repeating: "AB", count: Self.sha256DigestLength))
    let padded256 = CardOperations.estonian2018Digest(sha256)
    let padLength = Self.p384DigestLength - Self.sha256DigestLength
    #expect(padded256.count == Self.p384DigestLength)
    #expect(padded256.prefix(padLength) == Data(repeating: 0, count: padLength))
    #expect(padded256.suffix(Self.sha256DigestLength) == sha256)

    let sha512 = Data((0..<Self.sha512DigestLength).map { UInt8($0) })
    let truncated512 = CardOperations.estonian2018Digest(sha512)
    #expect(truncated512 == sha512.prefix(Self.p384DigestLength))

    let paddedHex = padded256.map { String(format: "%02X", $0) }.joined()
    let sha384Hex = String(repeating: "CD", count: Self.p384DigestLength)
    let sigHex = String(repeating: "99", count: Self.p384RawSignatureLength)

    let channel = ScriptedChannel([
      ("00A4000C", "9000"),
      ("002000010C" + Self.padFF12Hex("1234"), "9000"),
      ("00A4000C", "9000"),
      ("00A4010C02ADF1", "9000"),
      ("002241A4098004FF200800840181", "9000"),
      ("0088000030" + paddedHex + "00", sigHex + "9000"),
      ("00A4000C", "9000"),
      ("00A4010C02ADF2", "9000"),
      ("002000850C" + Self.padFF12Hex("12345"), "9000"),
      ("002241B6098004FF15080084019F", "9000"),
      ("002A9E9A30" + sha384Hex + "00", sigHex + "9000"),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    guard let pin1 = Pin1(digits: "1234"), let pin2 = Pin2(digits: "12345") else {
      Issue.record("synthetic PIN failed to construct")
      return
    }
    try operations.verifyPin1(pin1.consumeForSingleTransmission())
    let authSig = try operations.computeAuthenticationSignature(
      overDigest: sha256,
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .ecdsa),
      expectedSignatureLength: ExpectedResponseLength(count: Self.p384RawSignatureLength)
    )
    #expect(authSig == WireHex.data(sigHex))

    try operations.verifyPin2(pin2.consumeForSingleTransmission())
    let signSig = try operations.computeQualifiedSignature(
      overDigest: WireHex.data(sha384Hex),
      algorithm: SigningAlgorithm(hash: .sha384, scheme: .ecdsa),
      expectedSignatureLength: ExpectedResponseLength(count: Self.p384RawSignatureLength)
    )
    #expect(signSig == WireHex.data(sigHex))
    #expect(channel.isExhausted)
  }
}
