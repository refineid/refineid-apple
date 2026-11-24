// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Estonian document-number parsing, `BinaryReadAssembler` empty-EOF retry,
/// three-try `Pin1Retention` / `PinAdmission`, ATR hints, `PrimedIdentity`
/// serialization, and Estonian X.509 `DistinguishedName` tests.
@Suite
internal struct EstonianDocumentNumberTests {
  private static let estonianAllowance = EstonianEidValues.pinRetryLimit
  private static let belowFloorAttempts = EstonianEidValues.pinRetryLimit - 1
  private static let lastTryAttempts: UInt8 = 1
  private static let longFormSingleByteLength: UInt8 = DerValues.longFormMask | 1

  @Test
  internal func documentNumberParsesValidAsciiAndTlvForms() throws {
    let docBytes = Data(EstonianEidTestFixture.syntheticDocNumber2025.utf8)
    let ascii = try #require(DocumentNumber(asciiBytes: docBytes))
    #expect(ascii.value == EstonianEidTestFixture.syntheticDocNumber2025)

    let octetTlv = try #require(
      DocumentNumber(
        tlvBytes: DerEncoder.tlv(EstonianEidValues.documentNumberTagOctetString, docBytes)
      )
    )
    #expect(octetTlv.value == EstonianEidTestFixture.syntheticDocNumber2025)

    let app26Tlv = try #require(
      DocumentNumber(
        tlvBytes: DerEncoder.tlv(EstonianEidValues.documentNumberTagApplication26, docBytes)
      )
    )
    #expect(app26Tlv.value == EstonianEidTestFixture.syntheticDocNumber2025)

    let printed = PrintedSerial(documentNumber: ascii)
    #expect(printed.value == EstonianEidTestFixture.syntheticDocNumber2025)
    #expect(TokenInstanceID(printedSerial: printed).value == "refineid-card-aa0000001")
  }

  @Test
  internal func documentNumberRejectsMalformedInputs() {
    let docBytes = Data(EstonianEidTestFixture.syntheticDocNumber2025.utf8)
    let wrongTag = DerValues.tagNull
    let longFormTlv =
      Data([
        EstonianEidValues.documentNumberTagOctetString,
        Self.longFormSingleByteLength,
        UInt8(docBytes.count),
      ]) + docBytes
    let trailingByteTlv =
      DerEncoder.tlv(EstonianEidValues.documentNumberTagOctetString, docBytes)
      + Data([FineidValues.pinPadByte])

    #expect(DocumentNumber(asciiBytes: Data("aa0000001".utf8)) == nil)
    #expect(DocumentNumber(asciiBytes: Data("AA000001".utf8)) == nil)
    #expect(DocumentNumber(asciiBytes: Data("A10000001".utf8)) == nil)
    #expect(DocumentNumber(asciiBytes: Data("AA00000010".utf8)) == nil)
    #expect(DocumentNumber(tlvBytes: DerEncoder.tlv(wrongTag, docBytes)) == nil)
    #expect(DocumentNumber(tlvBytes: longFormTlv) == nil)
    #expect(DocumentNumber(tlvBytes: trailingByteTlv) == nil)
  }

  @Test
  internal func binaryReadAssemblerRetriesOnceOnEmptyEndOfFile() throws {
    let docBytes = Data(EstonianEidTestFixture.syntheticDocNumber2025.utf8)
    var assembler = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: DocumentNumber.probeReadCap
    )
    let firstRead = CommandApdu.readBinary(
      offset: try #require(ReadOffset(value: .zero)),
      expectedLength: try #require(ExpectedResponseLength(count: DocumentNumber.probeReadCap))
    )
    #expect(assembler.nextStep == .transmit(firstRead))
    assembler.accept(try EstonianEidTestFixture.responseApdu(Data(), status: .endOfFile))

    let retryRead = CommandApdu.readBinary(
      offset: try #require(ReadOffset(value: .zero)),
      expectedLength: try #require(ExpectedResponseLength(count: ExpectedResponseLength.maximum))
    )
    #expect(assembler.nextStep == .transmit(retryRead))
    assembler.accept(try EstonianEidTestFixture.responseApdu(docBytes, status: .success))
    #expect(assembler.nextStep == .complete(docBytes))
  }

  @Test
  internal func binaryReadAssemblerStopsOnSecondEmptyEndOfFile() throws {
    var assembler = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: DocumentNumber.probeReadCap
    )
    assembler.accept(try EstonianEidTestFixture.responseApdu(Data(), status: .endOfFile))
    assembler.accept(try EstonianEidTestFixture.responseApdu(Data(), status: .endOfFile))
    #expect(assembler.nextStep == .failed(.emptyFile))
  }

  @Test
  internal func binaryReadAssemblerEnforcesCapOnRetryAndCompletesMidFileEof() throws {
    var capped = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: DocumentNumber.probeReadCap
    )
    capped.accept(try EstonianEidTestFixture.responseApdu(Data(), status: .endOfFile))
    let oversized = Data(repeating: UInt8(ascii: "A"), count: DocumentNumber.probeReadCap + 1)
    capped.accept(try EstonianEidTestFixture.responseApdu(oversized, status: .success))
    #expect(capped.nextStep == .failed(.oversizedChunk))

    var midFile = BinaryReadAssembler(mode: .toEndOfFile, expectedLength: nil)
    let firstChunk = Data(repeating: UInt8(ascii: "B"), count: ReadChunkLength.plain.count)
    midFile.accept(try EstonianEidTestFixture.responseApdu(firstChunk, status: .success))
    midFile.accept(try EstonianEidTestFixture.responseApdu(Data(), status: .endOfFile))
    #expect(midFile.nextStep == .complete(firstChunk))
  }

  @Test
  internal func primedIdentityRoundTripsEstonian2025And2018Json() throws {
    let documentNumber = try #require(
      DocumentNumber(asciiBytes: Data(EstonianEidTestFixture.syntheticDocNumber2025.utf8))
    )
    let printed = PrintedSerial(documentNumber: documentNumber)
    let est2025Chip = try #require(ChipSerial(value: "0123456789ABCDEF"))
    let prime2025 = try #require(
      PrimedIdentity(
        can: EstonianEidTestFixture.syntheticCan,
        certificate: EstonianEidTestFixture.syntheticAuthCertDer,
        issuer: nil,
        chipSerial: est2025Chip,
        activationCheck: .passed,
        printedSerial: printed,
        cardNumbering: .estonian2025
      )
    )
    let decoded2025 = try JSONDecoder().decode(
      PrimedIdentity.self, from: JSONEncoder().encode(prime2025)
    )
    #expect(decoded2025 == prime2025)
    #expect(decoded2025.resolvedPrintedSerial == printed)

    let prime2018 = try #require(
      PrimedIdentity(
        can: EstonianEidTestFixture.syntheticCan,
        certificate: EstonianEidTestFixture.syntheticSignCertDer,
        issuer: nil,
        chipSerial: ChipSerial(documentNumber: documentNumber),
        activationCheck: .passed,
        printedSerial: printed,
        cardNumbering: .estonian2018
      )
    )
    let decoded2018 = try JSONDecoder().decode(
      PrimedIdentity.self, from: JSONEncoder().encode(prime2018)
    )
    #expect(decoded2018 == prime2018)
    #expect(decoded2018.resolvedPrintedSerial == printed)
  }

  @Test
  internal func threeTryPristineAllowanceControlsPin1RetentionAndAdmission() throws {
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let two = try #require(RetryCount(attemptsRemaining: Self.belowFloorAttempts))
    let one = try #require(RetryCount(attemptsRemaining: Self.lastTryAttempts))

    #expect(three.isPristine(allowance: Self.estonianAllowance))
    #expect(!two.isPristine(allowance: Self.estonianAllowance))
    #expect(
      Pin1Retention.permitsHolding(after: .remaining(three), allowance: Self.estonianAllowance)
    )
    #expect(
      !Pin1Retention.permitsHolding(after: .remaining(two), allowance: Self.estonianAllowance)
    )
    #expect(
      PinAdmission(
        probe: .remaining(three),
        spending: .heldPin1,
        pristineAllowance: Self.estonianAllowance
      ) == .proceed
    )
    #expect(
      PinAdmission(
        probe: .remaining(two),
        spending: .heldPin1,
        pristineAllowance: Self.estonianAllowance
      ) == .retryFloor(.refuseLowAttempts)
    )
    #expect(
      PinAdmission(
        probe: .remaining(one),
        spending: .entered,
        pristineAllowance: Self.estonianAllowance
      ) == .retryFloor(.refuseLowAttempts)
    )
  }

  @Test
  internal func answerToResetDetectsEstonian2018MarkersOnly() {
    let syntheticV8 = EstonianEidTestFixture.atr(
      historicalBytes: EstonianEidValues.legacyCosmoV8Marker
    )
    let syntheticCosmoX = EstonianEidTestFixture.atr(
      historicalBytes: EstonianEidValues.legacyCosmoXMarker
    )
    let syntheticOther = EstonianEidTestFixture.atr(historicalBytes: Array("FINEID".utf8))

    #expect(AnswerToReset.indicatesEstonian2018(bytes: syntheticV8))
    #expect(AnswerToReset.indicatesEstonian2018(bytes: syntheticCosmoX))
    #expect(!AnswerToReset.indicatesEstonian2018(bytes: syntheticOther))
  }

  @Test
  internal func distinguishedNameParsesEstonianCommaSeparatedCommonNames() throws {
    let estonianCert = try MockCardCertificate.makeCertificate(
      commonName: "DOE,JANE,39901019999"
    )
    #expect(DistinguishedName.holderLine(fromCertificate: estonianCert) == "DOE JANE")
    #expect(DistinguishedName.identifier(fromCertificate: estonianCert) == "39901019999")

    let multiWordCert = try MockCardCertificate.makeCertificate(
      commonName: "TAMM,MARI-LIIS ANNA,49902029998"
    )
    #expect(
      DistinguishedName.holderLine(fromCertificate: multiWordCert) == "TAMM MARI-LIIS ANNA"
    )
    #expect(DistinguishedName.identifier(fromCertificate: multiWordCert) == "49902029998")
  }
}
