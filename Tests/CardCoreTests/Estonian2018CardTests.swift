// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// EstEID 2018 / 2018 v2 (IDEMIA Cosmo v8 / Cosmo X, ID1 Developer Guide 2025)
/// application selection, certificate reads, document number, and counter tests.
@Suite
internal struct Estonian2018CardTests {
  private static let estonianAllowance = EstonianEidValues.pinRetryLimit

  @Test
  internal func applicationSelectFallsBackToCosmoV8AndCosmoX() throws {
    let success = EstonianEidTestFixture.status(.success)
    let missing = EstonianEidTestFixture.status(.fileNotFound)
    let cosmoV8 = TypedScriptedChannel([
      (EstonianEidTestFixture.selectApp, missing),
      (CommandApdu.selectApplication(.estonian2018Application).encoded, success),
    ])
    let opsV8 = CardOperations(channel: cosmoV8)
    try opsV8.selectCardApplication()
    #expect(opsV8.resolvedNumbering == .estonian2018)
    #expect(opsV8.pristineRetryAllowance == Self.estonianAllowance)
    #expect(cosmoV8.isExhausted)

    let cosmoX = TypedScriptedChannel([
      (EstonianEidTestFixture.selectApp, missing),
      (CommandApdu.selectApplication(.estonian2018Application).encoded, missing),
      (CommandApdu.selectApplication(.estonian2018V2Application).encoded, success),
    ])
    let opsX = CardOperations(channel: cosmoX)
    try opsX.selectCardApplication()
    #expect(opsX.resolvedNumbering == .estonian2018)
    #expect(cosmoX.isExhausted)
  }

  @Test
  internal func estonian2018CertificateReadsAndRekeyFallbacks() throws {
    let success = EstonianEidTestFixture.status(.success)
    let missing = EstonianEidTestFixture.status(.fileNotFound)
    let plainRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: ReadChunkLength.plain.count
    )
    let authResponse = EstonianEidTestFixture.response(
      EstonianEidTestFixture.syntheticAuthCertDer, status: .success
    )
    let signResponse = EstonianEidTestFixture.response(
      EstonianEidTestFixture.syntheticSignCertDer, status: .success
    )
    let channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectAwp, success),
      (EstonianEidTestFixture.selectEf(.estonian2018AuthCertificate), missing),
      (EstonianEidTestFixture.selectByFid(.estonian2018AuthCertificate), missing),
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectAwp, success),
      (EstonianEidTestFixture.selectEf(.estonian2018SecondAuthCertificate), success),
      (plainRead, authResponse),
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectQscd, success),
      (EstonianEidTestFixture.selectEf(.estonian2018SignatureCertificate), missing),
      (EstonianEidTestFixture.selectByFid(.estonian2018SignatureCertificate), missing),
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectQscd, success),
      (EstonianEidTestFixture.selectEf(.estonian2018SecondSignatureCertificate), success),
      (plainRead, signResponse),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    #expect(
      try operations.readCertificate(.authentication) == EstonianEidTestFixture.syntheticAuthCertDer
    )
    #expect(
      try operations.readCertificate(.qualifiedSignature)
        == EstonianEidTestFixture.syntheticSignCertDer
    )
    #expect(throws: CardOperationError.selectRejected(.fileNotFound)) {
      _ = try operations.readCertificate(.issuing)
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2018DocumentNumberReadsD003TlvAndFallsBackTo5007() throws {
    let success = EstonianEidTestFixture.status(.success)
    let missing = EstonianEidTestFixture.status(.fileNotFound)
    let docBytes = Data(EstonianEidTestFixture.syntheticDocNumber2018.utf8)
    let tlvPayload = DerEncoder.tlv(EstonianEidValues.documentNumberTagApplication26, docBytes)
    let plainRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: ReadChunkLength.plain.count
    )
    let capRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: DocumentNumber.probeReadCap
    )
    let d003Channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectEf(.estonianDocumentNumberTlv), success),
      (plainRead, EstonianEidTestFixture.response(tlvPayload, status: .success)),
    ])
    let serials = try CardOperations(
      channel: d003Channel, numbering: .estonian2018
    ).readCardIdentitySerials()
    #expect(serials.chipSerial.value == EstonianEidTestFixture.syntheticDocNumber2018)
    #expect(serials.printedSerial.value == EstonianEidTestFixture.syntheticDocNumber2018)
    #expect(d003Channel.isExhausted)

    let fallbackChannel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectEf(.estonianDocumentNumberTlv), missing),
      (EstonianEidTestFixture.selectByFid(.estonianDocumentNumberTlv), missing),
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectChild(.estonianLegacyPersonalDataDirectory), success),
      (EstonianEidTestFixture.selectEf(.estonianDocumentNumberPlain), success),
      (capRead, EstonianEidTestFixture.response(docBytes, status: .success)),
    ])
    let fallbackDoc = try CardOperations(
      channel: fallbackChannel, numbering: .estonian2018
    ).readEstonian2018DocumentNumber()
    #expect(fallbackDoc.value == EstonianEidTestFixture.syntheticDocNumber2018)
    #expect(fallbackChannel.isExhausted)
  }

  @Test
  internal func estonian2018ProbesCountersAndPinLengths() throws {
    let success = EstonianEidTestFixture.status(.success)
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let threeStatus = EstonianEidTestFixture.status(
      try EstonianEidTestFixture.remaining(Self.estonianAllowance)
    )
    let channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (CommandApdu.readRetryCounter(role: .pin1, references: .estonian2018).encoded, threeStatus),
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectQscd, success),
      (CommandApdu.readRetryCounter(role: .pin2, references: .estonian2018).encoded, threeStatus),
      (EstonianEidTestFixture.selectRoot2018, success),
      (CommandApdu.readRetryCounter(role: .puk, references: .estonian2018).encoded, threeStatus),
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
    EstonianEidTestFixture.expectStandardEstonianPinLengths(try operations.readCardPinLengths())
    #expect(channel.isExhausted)
  }
}
