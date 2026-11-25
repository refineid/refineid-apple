// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

extension Estonian2025CardTests {
  internal static func estonian2025SigningScript(
    digest: Data,
    algorithm: SigningAlgorithm,
    sigLength: ExpectedResponseLength
  ) throws -> [(Data, Data)] {
    let success = EstonianEidTestFixture.status(.success)
    let plainRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: ReadChunkLength.plain.count
    )
    let sigResponse = EstonianEidTestFixture.response(
      EstonianEidTestFixture.syntheticSignatureBytes, status: .success
    )
    var script = EstonianEidTestFixture.estonian2025DiscoveryExchanges(plainRead: plainRead)
    script.append(contentsOf: [
      (
        EstonianEidTestFixture.verifyPin1Payload(
          EstonianEidTestFixture.samplePin1, references: .estonian2025
        ),
        success
      ),
      (
        CommandApdu.selectSigningEnvironment(
          algorithm: algorithm, keyReference: EstonianEidTestFixture.rekeyedAuthKeyRef
        ).encoded,
        success
      ),
      (CommandApdu.loadExternalHash(digest).encoded, success),
      (CommandApdu.computeSignatureOverLoadedHash(exactLength: sigLength).encoded, sigResponse),
      (
        EstonianEidTestFixture.verifyPin2Payload(
          EstonianEidTestFixture.samplePin2, references: .estonian2025
        ),
        success
      ),
      (
        CommandApdu.selectSigningEnvironment(
          algorithm: algorithm, keyReference: EstonianEidTestFixture.rekeyedSignKeyRef
        ).encoded,
        success
      ),
      (CommandApdu.loadExternalHash(digest).encoded, success),
      (CommandApdu.computeSignatureOverLoadedHash(exactLength: sigLength).encoded, sigResponse),
    ])
    return script
  }

  @Test
  internal func estonian2025ProbeCredentialsAndActivationMatchThreeTryAllowance() throws {
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let threeRemaining = try EstonianEidTestFixture.remaining(Self.estonianAllowance)
    let channel = TypedScriptedChannel([
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .citizen).encoded,
        EstonianEidTestFixture.status(.referenceDataNotFound)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .organization).encoded,
        EstonianEidTestFixture.status(.referenceDataNotFound)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .estonian2025).encoded,
        EstonianEidTestFixture.status(threeRemaining)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin2, references: .estonian2025).encoded,
        EstonianEidTestFixture.status(threeRemaining)
      ),
      (
        CommandApdu.readCredentialAttributes(role: .puk, references: .estonian2025).encoded,
        EstonianEidTestFixture.response(
          EstonianEidTestFixture.pinAttributesResponse(attemptsRemaining: Self.estonianAllowance),
          status: .success
        )
      ),
      (
        CommandApdu.readCredentialAttributes(role: .pin2, references: .estonian2025).encoded,
        EstonianEidTestFixture.response(
          EstonianEidTestFixture.pinChangedFlagResponse(changed: true),
          status: .success
        )
      ),
    ])
    let operations = CardOperations(channel: channel)
    let report = try operations.probeCredentials()
    #expect(report.pin1 == .remaining(three))
    #expect(report.pin2 == .remaining(three))
    #expect(report.puk == .remaining(three))
    #expect(report.pristineAllowance == Self.estonianAllowance)
    #expect(!report.pin2RequiresChangeBeforeSigning)
    #expect(operations.activationClassification() == .estonian)
    #expect(
      operations.activationNeeds(scheme: .presetActivationPin)
        == CardActivationNeeds(pin1: false, pin2: false)
    )
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025DetectsUnchangedInitialPin2BeforeSigning() throws {
    let threeRemaining = try EstonianEidTestFixture.remaining(Self.estonianAllowance)
    let unchangedAttributes = EstonianEidTestFixture.response(
      EstonianEidTestFixture.pinChangedFlagResponse(changed: false),
      status: .success
    )
    let channel = TypedScriptedChannel([
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .estonian2025).encoded,
        EstonianEidTestFixture.status(threeRemaining)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin2, references: .estonian2025).encoded,
        EstonianEidTestFixture.status(threeRemaining)
      ),
      (
        CommandApdu.readCredentialAttributes(role: .puk, references: .estonian2025).encoded,
        EstonianEidTestFixture.response(
          EstonianEidTestFixture.pinAttributesResponse(attemptsRemaining: Self.estonianAllowance),
          status: .success
        )
      ),
      (
        CommandApdu.readCredentialAttributes(role: .pin2, references: .estonian2025).encoded,
        unchangedAttributes
      ),
      (
        CommandApdu.readCredentialAttributes(role: .pin2, references: .estonian2025).encoded,
        unchangedAttributes
      ),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    let report = try operations.probeCredentials()
    #expect(report.pin2RequiresChangeBeforeSigning)
    #expect(try operations.requiresPin2ChangeBeforeSigning())
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonianVerifyAndProbeCommandsMatchSpecificationBytes() {
    let verify2025 = EstonianEidTestFixture.verifyPin1Payload(
      EstonianEidTestFixture.samplePin1, references: .estonian2025
    )
    let expectedVerify2025 =
      Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insVerify,
        Iso7816Values.verifyModeP1,
        EstonianEidValues.pin1Reference2025,
        UInt8(FineidValues.pinStoredLength),
      ])
      + EstonianEidTestFixture.paddedPinBlock(
        EstonianEidTestFixture.samplePin1, padByte: FineidValues.pinPadByte
      )
    #expect(verify2025 == expectedVerify2025)

    let verify2018 = EstonianEidTestFixture.verifyPin1Payload(
      EstonianEidTestFixture.samplePin1, references: .estonian2018
    )
    let expectedVerify2018 =
      Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insVerify,
        Iso7816Values.verifyModeP1,
        EstonianEidValues.pin1Reference2018,
        UInt8(FineidValues.pinStoredLength),
      ])
      + EstonianEidTestFixture.paddedPinBlock(
        EstonianEidTestFixture.samplePin1, padByte: EstonianEidValues.legacyPinPadByte
      )
    #expect(verify2018 == expectedVerify2018)

    let probe2018 = CommandApdu.readRetryCounter(role: .pin2, references: .estonian2018).encoded
    #expect(
      probe2018
        == Data([
          Iso7816Values.classInterindustry,
          Iso7816Values.insVerify,
          Iso7816Values.verifyModeP1,
          EstonianEidValues.pin2Reference2018,
        ])
    )
  }

  @Test
  internal func estonian2025UnblockCommandMatchesSpecificationBytes() {
    let unblock2025 = EstonianEidTestFixture.unblockPin1Payload(
      puk: EstonianEidTestFixture.samplePuk,
      new: EstonianEidTestFixture.sampleResetPin1,
      references: .estonian2025
    )
    let expectedUnblock2025 =
      Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insResetRetryCounter,
        Iso7816Values.resetWithPukThenNewP1,
        EstonianEidValues.pin1Reference2025,
        UInt8(FineidValues.pinStoredLength * 2),
      ])
      + EstonianEidTestFixture.paddedPinBlock(
        EstonianEidTestFixture.samplePuk, padByte: FineidValues.pinPadByte
      )
      + EstonianEidTestFixture.paddedPinBlock(
        EstonianEidTestFixture.sampleResetPin1, padByte: FineidValues.pinPadByte
      )
    #expect(unblock2025 == expectedUnblock2025)
  }

  @Test
  internal func estonian2025ChangesPins1And2() throws {
    let success = EstonianEidTestFixture.status(.success)
    let lengths = CardPinLengths.notListed(numbering: .estonian2025)
    let channel = TypedScriptedChannel([
      (
        EstonianEidTestFixture.changePin1Payload(
          current: EstonianEidTestFixture.samplePin1,
          new: EstonianEidTestFixture.sampleNewPin1,
          references: .estonian2025
        ),
        success
      ),
      (
        EstonianEidTestFixture.changePin2Payload(
          current: EstonianEidTestFixture.samplePin2,
          new: EstonianEidTestFixture.sampleNewPin2,
          references: .estonian2025
        ),
        success
      ),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    guard
      let oldPin1 = Pin1(digits: EstonianEidTestFixture.samplePin1),
      let newPin1 = Pin1(digits: EstonianEidTestFixture.sampleNewPin1),
      let oldPin2 = Pin2(digits: EstonianEidTestFixture.samplePin2),
      let newPin2 = Pin2(digits: EstonianEidTestFixture.sampleNewPin2)
    else {
      Issue.record("synthetic PIN failed to construct")
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
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025UnblocksPins1And2InSingleCommand() throws {
    let success = EstonianEidTestFixture.status(.success)
    let lengths = CardPinLengths.notListed(numbering: .estonian2025)
    let channel = TypedScriptedChannel([
      (
        EstonianEidTestFixture.unblockPin1Payload(
          puk: EstonianEidTestFixture.samplePuk,
          new: EstonianEidTestFixture.sampleResetPin1,
          references: .estonian2025
        ),
        success
      ),
      (
        EstonianEidTestFixture.unblockPin2Payload(
          puk: EstonianEidTestFixture.samplePuk,
          new: EstonianEidTestFixture.sampleResetPin2,
          references: .estonian2025
        ),
        success
      ),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    guard
      let puk1 = Puk(digits: EstonianEidTestFixture.samplePuk),
      let resetPin1 = Pin1(digits: EstonianEidTestFixture.sampleResetPin1),
      let puk2 = Puk(digits: EstonianEidTestFixture.samplePuk),
      let resetPin2 = Pin2(digits: EstonianEidTestFixture.sampleResetPin2)
    else {
      Issue.record("synthetic unblock credentials failed to construct")
      return
    }
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
  internal func estonian2018DocumentNumberRethrowsSecurityNotSatisfiedImmediately() {
    let channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, EstonianEidTestFixture.status(.success)),
      (
        EstonianEidTestFixture.selectEf(.estonianDocumentNumberTlv),
        EstonianEidTestFixture.status(.securityNotSatisfied)
      ),
      (
        EstonianEidTestFixture.selectByFid(.estonianDocumentNumberTlv),
        EstonianEidTestFixture.status(.securityNotSatisfied)
      ),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    #expect(throws: CardOperationError.selectRejected(.securityNotSatisfied)) {
      _ = try operations.readEstonian2018DocumentNumber()
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func selectByPathRejectsEmptyAndOversizedPaths() {
    let overflowCount = Int(UInt8.max) / 2 + 1
    #expect(CommandApdu.selectByPath([]) == nil)
    let oversized = Array(repeating: FileIdentifier.estonianAwpDirectory, count: overflowCount)
    #expect(CommandApdu.selectByPath(oversized) == nil)
  }
}
