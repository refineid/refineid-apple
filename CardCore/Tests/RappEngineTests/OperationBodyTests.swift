// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Replays the operation-protocol bodies an independent encoder produced from
// the RAPP v26.10.9 schemas. Every body is produced through the engine's own
// encoders rather than assembled here, so the test proves what a peer would
// actually receive.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP operation bodies against the vendored bytes")
internal struct OperationBodyTests {
  /// One status report and the vector it must reproduce.
  private struct StatusCase {
    let name: String
    let state: OperationState
    let retired: Bool
  }

  /// One completed answer, the operation it answers, and its vector.
  private struct AnswerCase {
    let name: String
    let result: CardOperationResult
    let operation: CardOperation
  }

  /// One typed request and the vector it must reproduce.
  private struct RequestCase {
    let name: String
    let profile: ProfileName
    let operation: CardOperation
  }

  private static func expected(_ corpus: OperationCorpus, _ name: String) throws -> String {
    guard let vector = corpus.vectors.first(where: { $0.name == name }) else {
      throw CorpusError.missingHandshake(name: name)
    }
    return vector.bodyHex
  }

  private static func reference(_ inputs: OperationInputs) throws -> OperationReference {
    OperationReference(
      operationIdentifier: try Data(hex: inputs.operationIdentifierReference),
      requestHash: try Data(hex: inputs.requestHashReference))
  }

  /// Every request shares its identifiers; only the typed operation differs.
  private static func request(
    _ inputs: OperationInputs, _ profile: ProfileName, _ operation: CardOperation
  ) throws -> OperationRequest {
    try OperationRequest(
      operationIdentifier: try Data(hex: inputs.operationIdentifierRequest),
      pairIdentifier: try Data(hex: inputs.pairIdentifier),
      sessionIdentifier: try Data(hex: inputs.sessionIdentifier),
      profile: profile,
      localStartMilliseconds: inputs.localStartMilliseconds,
      expiresAfterMilliseconds: inputs.expiresAfterMilliseconds,
      operation: operation)
  }

  private static func encoded(_ message: TypedMessage) throws -> String {
    guard let body = try message.encodedBody() else {
      throw CorpusError.missingHandshake(name: "encodable body")
    }
    return body.hex
  }

  @Test("The vendored bodies are the current revision")
  internal func vectorIdentity() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    #expect(corpus.format == "fi.refineid.rapp.operation-vectors-v1")
    #expect(corpus.protocolDocumentVersion == "26.10.9")
    #expect(corpus.vectors.count == 34)
  }

  @Test("Every typed request matches byte for byte and hashes over the pairing")
  internal func requestBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let inputs = corpus.fixedInputs
    let cases: [RequestCase] = [
      RequestCase(name: "request-inspect-card", profile: .cardStatus, operation: .inspectCard),
      RequestCase(name: "request-read-identity", profile: .cardStatus, operation: .readIdentity),
      RequestCase(
        name: "request-read-certificate-authentication", profile: .authentication,
        operation: .readCertificate(kind: .authentication)),
      RequestCase(
        name: "request-read-certificate-signature", profile: .documentSigning,
        operation: .readCertificate(kind: .signature)),
      RequestCase(
        name: "request-browser-authenticate", profile: .authentication,
        operation: .browserAuthenticate(
          origin: inputs.origin, keyProfile: .rsa3072, algorithm: .rsaPkcs1Sha256,
          digest: try Data(hex: inputs.digestSha256))),
      RequestCase(
        name: "request-sign-document", profile: .documentSigning,
        operation: .signDocument(
          documentName: inputs.documentName, keyProfile: .ecdsaP384, algorithm: .ecdsaSha384,
          digest: try Data(hex: inputs.digestSha384))),
    ]
    for testCase in cases {
      let request = try Self.request(inputs, testCase.profile, testCase.operation)
      let message = TypedMessage.operationRequest(request)
      #expect(
        try Self.encoded(message) == (try Self.expected(corpus, testCase.name)), "\(testCase.name)")
      let vector = try #require(corpus.vectors.first { $0.name == testCase.name })
      #expect(try request.requestHash().hex == vector.requestHashHex, "\(testCase.name)")
      let parsed = try OperationRequest.from(
        wireBody: try decodedMap(try Data(hex: vector.bodyHex)),
        pairIdentifier: try Data(hex: inputs.pairIdentifier),
        sessionIdentifier: try Data(hex: inputs.sessionIdentifier),
        localStartMilliseconds: inputs.localStartMilliseconds)
      #expect(parsed == request, "\(testCase.name) parses back")
    }
  }

  @Test("The acknowledgement carries the reference")
  internal func referenceBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let reference = try Self.reference(corpus.fixedInputs)
    #expect(
      try Self.encoded(.operationResultAck(reference))
        == (try Self.expected(corpus, "result-ack")))
  }

  @Test("A status request and every status report match byte for byte")
  internal func statusBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let inputs = corpus.fixedInputs
    let identifier = try Data(hex: inputs.operationIdentifierStatus)
    let requestHash = try Data(hex: inputs.requestHashStatus)

    #expect(
      try Self.encoded(.operationStatusRequest(operationIdentifier: identifier))
        == (try Self.expected(corpus, "status-request")))

    let cases: [StatusCase] = [
      StatusCase(name: "status-in-flight", state: .executing, retired: false),
      StatusCase(name: "status-completed-unretired", state: .deliveryUncertain, retired: false),
      StatusCase(name: "status-completed-retired", state: .completed, retired: true),
      StatusCase(name: "status-ambiguous", state: .ambiguous, retired: false),
    ]
    for testCase in cases {
      let report = StatusReport(
        operationIdentifier: identifier, known: true, state: testCase.state,
        requestHash: requestHash, retired: testCase.retired)
      #expect(
        try Self.encoded(.operationStatus(report)) == (try Self.expected(corpus, testCase.name)),
        "\(testCase.name)")
    }

    let unknown = StatusReport(
      operationIdentifier: identifier, known: false, state: nil, requestHash: nil)
    #expect(
      try Self.encoded(.operationStatus(unknown))
        == (try Self.expected(corpus, "status-unknown")))
  }

  @Test("An unknown status omits its absent fields rather than nulling them")
  internal func unknownStatusOmitsFields() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let unknown = StatusReport(
      operationIdentifier: try Data(hex: corpus.fixedInputs.operationIdentifierStatus),
      known: false, state: nil, requestHash: nil)
    #expect(unknown.wireBody.count == 2)
  }

  @Test("Each registered protocol error matches byte for byte")
  internal func errorBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let identifier = try Data(hex: corpus.fixedInputs.operationIdentifierError)
    let cases: [(String, ProtocolErrorMessage)] = [
      ("error-unknown-operation-with-id", .unknownOperation(operationIdentifier: identifier)),
      ("error-unknown-operation-bare", .unknownOperation(operationIdentifier: nil)),
      ("error-duplicate-operation", .duplicateOperation(operationIdentifier: identifier)),
      ("error-operation-failed", .operationFailed(operationIdentifier: identifier)),
    ]
    for (name, error) in cases {
      #expect(try Self.encoded(.error(error)) == (try Self.expected(corpus, name)), "\(name)")
      let decoded = ProtocolErrorMessage.from(
        wireBody: try decodedMap(try Data(hex: try Self.expected(corpus, name))))
      #expect(decoded == error, "\(name) decodes by name")
    }
  }

  @Test("Every completed result matches byte for byte and reads back as its answer")
  internal func completedResultBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let inputs = corpus.fixedInputs
    let reference = try Self.reference(inputs)
    let inspection = inputs.inspection
    var inspected = CardInspection(
      pin1Factory: inspection.pin1Factory, pin2Factory: inspection.pin2Factory,
      pin1Attempts: inspection.pin1Attempts, pin2Attempts: inspection.pin2Attempts,
      pukAttempts: inspection.pukAttempts)
    inspected.answerToReset = try Data(hex: inputs.answerToReset)
    let identity = CardIdentity(
      holderName: inputs.holderName, cardIdentifier: inputs.cardIdentifier,
      issuanceDate: inputs.issuanceDate, expirationDate: inputs.expirationDate,
      certificates: [try Data(hex: inputs.certificateDer)], tokenDisplayName: nil)
    let cases: [AnswerCase] = [
      AnswerCase(
        name: "result-completed-inspection", result: .inspection(inspected),
        operation: .inspectCard),
      AnswerCase(
        name: "result-completed-identity", result: .identity(identity),
        operation: .readIdentity),
      AnswerCase(
        name: "result-completed-certificate",
        result: .certificate(try Data(hex: inputs.certificateDer)),
        operation: .readCertificate(kind: .authentication)),
      AnswerCase(
        name: "result-completed-signature",
        result: .signature(try Data(hex: inputs.signatureBytes)),
        operation: .browserAuthenticate(
          origin: inputs.origin, keyProfile: .rsa3072, algorithm: .rsaPkcs1Sha256,
          digest: try Data(hex: inputs.digestSha256))),
    ]
    for testCase in cases {
      let name = testCase.name
      let result = testCase.result
      let operation = testCase.operation
      let message = OperationResultMessage.completed(reference: reference, result: result)
      #expect(try message.encoded().hex == (try Self.expected(corpus, name)), "\(name)")
      let decoded = try OperationResultMessage.decode(
        try Data(hex: try Self.expected(corpus, name)))
      #expect(decoded == message, "\(name) decodes from the vendored bytes")
      #expect(try decoded.typedResult(for: operation) == result, "\(name) answers its operation")
    }
  }

  @Test("Every registered failure matches byte for byte and decodes back")
  internal func failureResultBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let reference = try Self.reference(corpus.fixedInputs)
    let cases: [(String, ProxyFailure)] = [
      ("result-rejected-user-cancelled", .userDenied),
      ("result-cancelled-operation-expired", .requestExpired),
      ("result-cancelled-operation-expired", .cancelled),
      ("result-cancelled-card-error", .cardRemovedBeforeTransmit),
      ("result-rejected-unsupported-parameter", .requestInvalidOrUnsupported),
      ("result-rejected-unauthorized", .unauthorized),
      ("result-rejected-operation-failed", .retryPolicyRefused),
      ("result-credential-rejected-card-blocked", .credentialRejected),
      ("result-rejected-invalid-credential", .invalidCredential(remainingRetries: 2)),
      ("result-ambiguous-card-error", .cardCompletionAmbiguous),
    ]
    for (name, failure) in cases {
      let message = OperationResultMessage.failure(reference: reference, failure: failure)
      #expect(try message.encoded().hex == (try Self.expected(corpus, name)), "\(name)")
      let decoded = try OperationResultMessage.decode(
        try Data(hex: try Self.expected(corpus, name)))
      #expect(decoded == message, "\(name) decodes from the vendored bytes")
    }
    let retired = OperationResultMessage.retired(
      reference: reference, disposition: .completed, preservedError: nil)
    #expect(
      try retired.encoded().hex == (try Self.expected(corpus, "result-retired-completed")))
  }

  @Test("A changed digest changes the request bytes")
  internal func changedDigestChangesTheBytes() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let inputs = corpus.fixedInputs
    var digest = try Data(hex: inputs.digestSha256)
    let first = try #require(digest.indices.first)
    digest[first] ^= 1
    let altered = TypedMessage.operationRequest(
      try Self.request(
        inputs, .authentication,
        .browserAuthenticate(
          origin: inputs.origin, keyProfile: .rsa3072, algorithm: .rsaPkcs1Sha256,
          digest: digest)))
    #expect(
      try Self.encoded(altered) != (try Self.expected(corpus, "request-browser-authenticate")))
  }
}
