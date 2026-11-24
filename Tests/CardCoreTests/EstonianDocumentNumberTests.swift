// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Estonian document-number parsing, `BinaryReadAssembler` empty-EOF retry,
/// and three-try `Pin1Retention` / `PinAdmission` tests.
@Suite
internal struct EstonianDocumentNumberTests {
  private static let syntheticDocNumber = "AA0000001"
  private static let syntheticDocNumberHex = "414130303030303031"
  private static let estonianAllowance: UInt8 = 3
  private static let belowFloorAttempts: UInt8 = 2
  private static let lastTryAttempts: UInt8 = 1

  @Test
  internal func documentNumberParsesValidAsciiAndTlvForms() throws {
    let ascii = try #require(DocumentNumber(asciiBytes: Data(Self.syntheticDocNumber.utf8)))
    #expect(ascii.value == Self.syntheticDocNumber)

    let octetTlv = try #require(
      DocumentNumber(tlvBytes: WireHex.data("0409" + Self.syntheticDocNumberHex))
    )
    #expect(octetTlv.value == Self.syntheticDocNumber)

    let app26Tlv = try #require(
      DocumentNumber(tlvBytes: WireHex.data("5A09" + Self.syntheticDocNumberHex))
    )
    #expect(app26Tlv.value == Self.syntheticDocNumber)

    let printed = PrintedSerial(documentNumber: ascii)
    #expect(printed.value == Self.syntheticDocNumber)
    #expect(TokenInstanceID(printedSerial: printed).value == "refineid-card-aa0000001")
  }

  @Test
  internal func documentNumberRejectsMalformedInputs() {
    #expect(DocumentNumber(asciiBytes: Data("aa0000001".utf8)) == nil)
    #expect(DocumentNumber(asciiBytes: Data("AA000001".utf8)) == nil)
    #expect(DocumentNumber(asciiBytes: Data("A10000001".utf8)) == nil)
    #expect(DocumentNumber(asciiBytes: Data("AA00000010".utf8)) == nil)
    #expect(DocumentNumber(tlvBytes: WireHex.data("0509" + Self.syntheticDocNumberHex)) == nil)
    #expect(DocumentNumber(tlvBytes: WireHex.data("048109" + Self.syntheticDocNumberHex)) == nil)
    #expect(
      DocumentNumber(tlvBytes: WireHex.data("0409" + Self.syntheticDocNumberHex + "00")) == nil
    )
  }

  @Test
  internal func binaryReadAssemblerRetriesOnceOnEmptyEndOfFile() throws {
    var assembler = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: DocumentNumber.probeReadCap
    )
    let firstRead = CommandApdu.readBinary(
      offset: try #require(ReadOffset(value: .zero)),
      expectedLength: try #require(ExpectedResponseLength(count: DocumentNumber.probeReadCap))
    )
    #expect(assembler.nextStep == .transmit(firstRead))
    assembler.accept(try #require(ResponseApdu(raw: WireHex.data("6282"))))
    let retryRead = CommandApdu.readBinary(
      offset: try #require(ReadOffset(value: .zero)),
      expectedLength: try #require(ExpectedResponseLength(count: ExpectedResponseLength.maximum))
    )
    #expect(assembler.nextStep == .transmit(retryRead))
    assembler.accept(
      try #require(ResponseApdu(raw: WireHex.data(Self.syntheticDocNumberHex + "9000")))
    )
    #expect(assembler.nextStep == .complete(Data(Self.syntheticDocNumber.utf8)))
  }

  @Test
  internal func binaryReadAssemblerStopsOnSecondEmptyEndOfFile() throws {
    var assembler = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: DocumentNumber.probeReadCap
    )
    assembler.accept(try #require(ResponseApdu(raw: WireHex.data("6282"))))
    assembler.accept(try #require(ResponseApdu(raw: WireHex.data("6282"))))
    #expect(assembler.nextStep == .failed(.emptyFile))
  }

  @Test
  internal func binaryReadAssemblerEnforcesCapOnRetryAndCompletesMidFileEof() throws {
    var capped = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: DocumentNumber.probeReadCap
    )
    capped.accept(try #require(ResponseApdu(raw: WireHex.data("6282"))))
    let oversized = String(repeating: "41", count: DocumentNumber.probeReadCap + 1)
    capped.accept(try #require(ResponseApdu(raw: WireHex.data(oversized + "9000"))))
    #expect(capped.nextStep == .failed(.oversizedChunk))

    var midFile = BinaryReadAssembler(mode: .toEndOfFile, expectedLength: nil)
    let firstChunk = String(repeating: "42", count: ReadChunkLength.plain.count)
    midFile.accept(try #require(ResponseApdu(raw: WireHex.data(firstChunk + "9000"))))
    midFile.accept(try #require(ResponseApdu(raw: WireHex.data("6282"))))
    #expect(midFile.nextStep == .complete(WireHex.data(firstChunk)))
  }

  @Test
  internal func primedIdentityRoundTripsEstonian2025And2018Json() throws {
    let documentNumber = try #require(
      DocumentNumber(asciiBytes: Data(Self.syntheticDocNumber.utf8))
    )
    let printed = PrintedSerial(documentNumber: documentNumber)
    let est2025Chip = try #require(ChipSerial(value: "0123456789ABCDEF"))
    let prime2025 = try #require(
      PrimedIdentity(
        can: "123456",
        certificate: WireHex.data("3004AABBCCDD"),
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
        can: "123456",
        certificate: WireHex.data("300411223344"),
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
    let syntheticV8 = WireHex.data("3B0080233F5365494400")
    let syntheticCosmoX = WireHex.data("3B0080233F546549443200")
    let syntheticOther = WireHex.data("3B008046494E45494400")

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
