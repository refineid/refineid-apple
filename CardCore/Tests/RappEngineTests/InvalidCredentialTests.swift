// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.9 invalid credential (section 10.2)")
internal struct InvalidCredentialTests {
  private static let reference = OperationReference(
    operationIdentifier: Data(repeating: 0x22, count: 16),
    requestHash: Data(repeating: 0x33, count: 32))

  @Test("A typo is a rejected result carrying the remaining attempts")
  internal func typoCarriesRemainingAttempts() throws {
    let result = OperationResultMessage.failure(
      reference: Self.reference, failure: .invalidCredential(remainingRetries: 2))
    #expect(result.status == .rejected)
    #expect(result.error == .invalidCredential)
    #expect(result.remainingRetries == 2)
    #expect(result.isConsistent)
    #expect(try OperationResultMessage.decode(try result.encoded()) == result)
  }

  @Test("A typo keeps the session and the pairing; a blocked credential does not")
  internal func onlyABlockedCredentialRevokes() {
    let typo = OperationResultMessage.failure(
      reference: Self.reference, failure: .invalidCredential(remainingRetries: 1))
    let blocked = OperationResultMessage.failure(
      reference: Self.reference, failure: .credentialRejected)
    #expect(!ProxyFailure.invalidCredential(remainingRetries: 1).closesSession)
    #expect(!RappOperationBridge.failureRevokesPairing(.operationResult(typo)))
    #expect(ProxyFailure.credentialRejected.closesSession)
    #expect(RappOperationBridge.failureRevokesPairing(.operationResult(blocked)))
  }

  @Test("The requester reads a typo as an invalid credential")
  internal func requesterReadsInvalidCredential() {
    #expect(
      RappTerminalReason(ProxyFailure.invalidCredential(remainingRetries: 3))
        == .invalidCredential)
  }
}
