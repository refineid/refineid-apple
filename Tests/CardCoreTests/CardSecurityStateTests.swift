// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@Suite
internal struct CardSecurityStateTests {
  @Test
  internal func signingFailsWithSecurityNotSatisfiedIfPin1WasNotVerified() throws {
    let mock = StatefulSmartCardMock()
    let operations = CardOperations(channel: mock)
    try operations.selectCardApplication()

    let digest = Data(repeating: 0xAA, count: 32)
    let algorithm = SigningAlgorithm(hash: .sha256, scheme: .ecdsa)

    #expect(throws: CardOperationError.signRejected(.securityNotSatisfied)) {
      _ = try operations.computeAuthenticationSignature(
        overDigest: digest,
        algorithm: algorithm,
        expectedSignatureLength: nil
      )
    }
    #expect(mock.computeSignatureCount == 0)
  }

  @Test
  internal func signingSucceedsAfterPin1Verification() throws {
    let mock = StatefulSmartCardMock()
    let operations = CardOperations(channel: mock)
    try operations.selectCardApplication()

    guard let pin1 = Pin1(digits: "1234") else {
      Issue.record("Failed to construct Pin1")
      return
    }
    try operations.verifyPin1(pin1.consumeForSingleTransmission())

    let digest = Data(repeating: 0xAA, count: 32)
    let algorithm = SigningAlgorithm(hash: .sha256, scheme: .ecdsa)

    let signature = try operations.computeAuthenticationSignature(
      overDigest: digest,
      algorithm: algorithm,
      expectedSignatureLength: nil
    )
    #expect(signature == mock.dummySignature)
    #expect(mock.verifyPin1Count == 1)
    #expect(mock.computeSignatureCount == 1)
  }

  @Test
  internal func applicationSelectionInvalidatesPreviousPin1Authentication() throws {
    let mock = StatefulSmartCardMock()
    let operations = CardOperations(channel: mock)
    try operations.selectCardApplication()

    // 1. Verify and sign successfully
    guard let pin1 = Pin1(digits: "1234") else {
      Issue.record("Failed to construct Pin1")
      return
    }
    try operations.verifyPin1(pin1.consumeForSingleTransmission())

    let digest = Data(repeating: 0xAA, count: 32)
    let algorithm = SigningAlgorithm(hash: .sha256, scheme: .ecdsa)
    _ = try operations.computeAuthenticationSignature(
      overDigest: digest,
      algorithm: algorithm,
      expectedSignatureLength: nil
    )
    #expect(mock.computeSignatureCount == 1)

    // 2. Next operation re-selects application/DF
    try operations.selectCardApplication()
    #expect(!mock.isPin1Authenticated)

    // 3. Attempting to sign without re-verification must fail with securityNotSatisfied
    #expect(throws: CardOperationError.signRejected(.securityNotSatisfied)) {
      _ = try operations.computeAuthenticationSignature(
        overDigest: digest,
        algorithm: algorithm,
        expectedSignatureLength: nil
      )
    }

    // 4. Re-verifying PIN1 restores security state and allows signature
    guard let pin1Second = Pin1(digits: "1234") else {
      Issue.record("Failed to construct Pin1")
      return
    }
    try operations.verifyPin1(pin1Second.consumeForSingleTransmission())

    let secondSignature = try operations.computeAuthenticationSignature(
      overDigest: digest,
      algorithm: algorithm,
      expectedSignatureLength: nil
    )
    #expect(secondSignature == mock.dummySignature)
    #expect(mock.verifyPin1Count == 2)
    #expect(mock.computeSignatureCount == 2)
  }

  @Test
  internal func consecutiveSigningsInHeldBurstSucceedWhenPin1IsReverified() throws {
    let mock = StatefulSmartCardMock()

    let digest1 = Data(repeating: 0x11, count: 32)
    let digest2 = Data(repeating: 0x22, count: 32)
    let algorithm = SigningAlgorithm(hash: .sha256, scheme: .ecdsa)

    // Burst request 1:
    let ops1 = CardOperations(channel: mock)
    try ops1.selectCardApplication()
    guard let pin1First = Pin1(digits: "1234") else {
      Issue.record("Failed to construct Pin1")
      return
    }
    try ops1.verifyPin1(pin1First.consumeForSingleTransmission())
    let sig1 = try ops1.computeAuthenticationSignature(
      overDigest: digest1,
      algorithm: algorithm,
      expectedSignatureLength: nil
    )
    #expect(sig1 == mock.dummySignature)

    // Burst request 2 (consecutive request in same hold, selecting application again):
    let ops2 = CardOperations(channel: mock)
    try ops2.selectCardApplication()
    guard let pin1Second = Pin1(digits: "1234") else {
      Issue.record("Failed to construct Pin1")
      return
    }
    try ops2.verifyPin1(pin1Second.consumeForSingleTransmission())
    let sig2 = try ops2.computeAuthenticationSignature(
      overDigest: digest2,
      algorithm: algorithm,
      expectedSignatureLength: nil
    )
    #expect(sig2 == mock.dummySignature)

    #expect(mock.selectCount == 2)
    #expect(mock.verifyPin1Count == 2)
    #expect(mock.computeSignatureCount == 2)
  }
}
