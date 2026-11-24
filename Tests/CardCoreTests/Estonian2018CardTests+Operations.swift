// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

extension Estonian2018CardTests {
  @Test
  internal func estonian2018ChangesPins1And2() throws {
    let success = EstonianEidTestFixture.status(.success)
    let lengths = CardPinLengths.notListed(numbering: .estonian2018)
    let channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (
        EstonianEidTestFixture.changePin1Payload(
          current: EstonianEidTestFixture.samplePin1,
          new: EstonianEidTestFixture.sampleNewPin1,
          references: .estonian2018
        ),
        success
      ),
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectQscd, success),
      (
        EstonianEidTestFixture.changePin2Payload(
          current: EstonianEidTestFixture.samplePin2,
          new: EstonianEidTestFixture.sampleNewPin2,
          references: .estonian2018
        ),
        success
      ),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
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
  internal func estonian2018UnblocksPins1And2InTwoSteps() throws {
    let success = EstonianEidTestFixture.status(.success)
    let lengths = CardPinLengths.notListed(numbering: .estonian2018)
    let verifyPuk = EstonianEidTestFixture.verifyPukPayload(
      EstonianEidTestFixture.samplePuk, references: .estonian2018
    )
    let channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (verifyPuk, success),
      (
        EstonianEidTestFixture.resetPin1Payload(
          EstonianEidTestFixture.sampleResetPin1, references: .estonian2018
        ),
        success
      ),
      (EstonianEidTestFixture.selectRoot2018, success),
      (verifyPuk, success),
      (EstonianEidTestFixture.selectQscd, success),
      (
        EstonianEidTestFixture.resetPin2Payload(
          EstonianEidTestFixture.sampleResetPin2, references: .estonian2018
        ),
        success
      ),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
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
  internal func estonian2018NormalizesDigestsToP384Width() {
    let sha256 = Data(
      repeating: UInt8(ascii: "A"), count: EstonianEidTestFixture.sha256DigestLength
    )
    let padded256 = CardOperations.estonian2018Digest(sha256)
    let padLength = EstonianEidValues.p384DigestLength - EstonianEidTestFixture.sha256DigestLength
    #expect(padded256.count == EstonianEidValues.p384DigestLength)
    #expect(padded256.prefix(padLength) == Data(repeating: .zero, count: padLength))
    #expect(padded256.suffix(EstonianEidTestFixture.sha256DigestLength) == sha256)

    let sha512 = Data((0..<EstonianEidTestFixture.sha512DigestLength).map { UInt8($0) })
    #expect(
      CardOperations.estonian2018Digest(sha512)
        == sha512.prefix(EstonianEidValues.p384DigestLength)
    )
  }

  @Test
  internal func estonian2018SignsAuthenticationWithInternalAuth() throws {
    let success = EstonianEidTestFixture.status(.success)
    let sha256 = Data(
      repeating: UInt8(ascii: "A"), count: EstonianEidTestFixture.sha256DigestLength
    )
    let padded256 = CardOperations.estonian2018Digest(sha256)
    let sigLength = try #require(
      ExpectedResponseLength(count: EstonianEidTestFixture.p384RawSignatureLength)
    )
    let sigResponse = EstonianEidTestFixture.response(
      EstonianEidTestFixture.syntheticSignatureBytes, status: .success
    )
    let channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (
        EstonianEidTestFixture.verifyPin1Payload(
          EstonianEidTestFixture.samplePin1, references: .estonian2018
        ),
        success
      ),
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectAwp, success),
      (CommandApdu.selectEstonian2018AuthenticationEnvironment().encoded, success),
      (CommandApdu.internalAuthenticate(overDigest: padded256).encoded, sigResponse),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    guard let pin1 = Pin1(digits: EstonianEidTestFixture.samplePin1) else {
      Issue.record("synthetic PIN1 failed to construct")
      return
    }
    try operations.verifyPin1(pin1.consumeForSingleTransmission())
    let authSig = try operations.computeAuthenticationSignature(
      overDigest: sha256,
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .ecdsa),
      expectedSignatureLength: sigLength
    )
    #expect(authSig == EstonianEidTestFixture.syntheticSignatureBytes)
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2018SignsQualifiedWithPsoCds() throws {
    let success = EstonianEidTestFixture.status(.success)
    let sha384 = Data(repeating: UInt8(ascii: "C"), count: EstonianEidValues.p384DigestLength)
    let sigLength = try #require(
      ExpectedResponseLength(count: EstonianEidTestFixture.p384RawSignatureLength)
    )
    let sigResponse = EstonianEidTestFixture.response(
      EstonianEidTestFixture.syntheticSignatureBytes, status: .success
    )
    let channel = TypedScriptedChannel([
      (EstonianEidTestFixture.selectRoot2018, success),
      (EstonianEidTestFixture.selectQscd, success),
      (
        EstonianEidTestFixture.verifyPin2Payload(
          EstonianEidTestFixture.samplePin2, references: .estonian2018
        ),
        success
      ),
      (CommandApdu.selectEstonian2018SigningEnvironment().encoded, success),
      (CommandApdu.computeSignature(overDigest: sha384).encoded, sigResponse),
    ])
    let operations = CardOperations(channel: channel, numbering: .estonian2018)
    guard let pin2 = Pin2(digits: EstonianEidTestFixture.samplePin2) else {
      Issue.record("synthetic PIN2 failed to construct")
      return
    }
    try operations.verifyPin2(pin2.consumeForSingleTransmission())
    let signSig = try operations.computeQualifiedSignature(
      overDigest: sha384,
      algorithm: SigningAlgorithm(hash: .sha384, scheme: .ecdsa),
      expectedSignatureLength: sigLength
    )
    #expect(signSig == EstonianEidTestFixture.syntheticSignatureBytes)
    #expect(channel.isExhausted)
  }
}
