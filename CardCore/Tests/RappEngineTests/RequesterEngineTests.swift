// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// What the requester makes of the custodian's messages (RAPP v26.10.21
/// §8.1, §10.1).
@Suite("RAPP requester operation engine")
internal struct RequesterEngineTests {
  private static func live() throws -> RequesterOperationEngine {
    var engine = RequesterOperationEngine()
    _ = try engine.begin(try inspectionRequest(OperationFixture.operationIdentifier))
    return engine
  }

  @Test("Messages for an operation that is not live are ignored")
  internal func staleMessagesAreIgnored() throws {
    var engine = try Self.live()
    let other = OperationFixture.otherOperation
    #expect(
      try engine.receive(
        .operationProgress(OperationProgressMessage(operationIdentifier: other, event: .queued)))
        == .ignored(operationIdentifier: other))
    #expect(
      try engine.receive(
        .operationResult(.failure(operationIdentifier: other, failure: .cardError)))
        == .ignored(operationIdentifier: other))
    #expect(
      try engine.receive(.error(.busy(other))) == .ignored(operationIdentifier: other))
    #expect(
      try engine.receive(
        .error(ProtocolErrorMessage(error: .operationFailed, operationIdentifier: nil)))
        == .peerError(.operationFailed))
  }

  @Test("A result that does not answer the live operation closes the session")
  internal func mismatchedAnswerIsAViolation() throws {
    var engine = try Self.live()
    let wrong = OperationResultMessage.completed(
      operationIdentifier: OperationFixture.operationIdentifier,
      result: .signature(OperationFixture.signature))
    #expect(throws: EngineError.authenticatedProtocolViolation(.invalidResult)) {
      _ = try engine.receive(.operationResult(wrong))
    }
  }

  @Test("A request from the custodian closes the session")
  internal func requestFromTheCustodianIsAViolation() throws {
    var engine = RequesterOperationEngine()
    #expect(throws: EngineError.authenticatedProtocolViolation(.requesterOnlyMessage)) {
      _ = try engine.receive(
        .operationRequest(try inspectionRequest(OperationFixture.operationIdentifier)))
    }
  }

  @Test("A closed session loses the live operation and forgets its identifiers")
  internal func sessionCloseForgetsEverything() throws {
    var engine = try Self.live()
    #expect(engine.sessionClosed() == OperationFixture.operationIdentifier)
    #expect(engine.sessionClosed() == nil)
    _ = try engine.begin(try inspectionRequest(OperationFixture.operationIdentifier))
  }
}
