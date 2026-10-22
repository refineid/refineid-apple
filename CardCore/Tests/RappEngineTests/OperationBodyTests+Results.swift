// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

/// One completed answer, the operation it answers, and its vector.
private struct AnswerCase {
  let name: String
  let result: CardOperationResult
  let operation: CardOperation
}

/// The bodies a custodian sends: results, errors, progress and card status.
extension OperationBodyTests {
  @Test("Every completed result matches byte for byte and reads back as its answer")
  internal func completedResultBodies() throws {
    let corpus = try Self.corpus()
    let inputs = corpus.fixedInputs
    let identifier = try RappOperationIdentifier(hex: inputs.operationIdentifierResult)
    let certificate = try Data(hex: inputs.certificateDer)
    let identity = try CardIdentity(
      holderName: inputs.holderName, cardIdentifier: inputs.cardIdentifier,
      issuanceDate: inputs.issuanceDate, expirationDate: inputs.expirationDate,
      certificates: [certificate], tokenDisplayName: nil)
    let batch = CardOperation.batchSignDocuments(
      documentNames: inputs.batchDocumentNames, keyProfile: .ecdsaP256, algorithm: .ecdsaSha256,
      digests: try inputs.batchDigestsSha256.map { try Data(hex: $0) })
    let cases: [AnswerCase] = [
      AnswerCase(
        name: "result-completed-inspection",
        result: .inspection(answerToReset: try Data(hex: inputs.answerToReset)),
        operation: .inspectCard),
      AnswerCase(
        name: "result-completed-identity", result: .identity(identity), operation: .readIdentity),
      AnswerCase(
        name: "result-completed-certificate", result: .certificate(certificate),
        operation: .readCertificate(kind: .authentication)),
      AnswerCase(
        name: "result-completed-signature",
        result: .signature(try Data(hex: inputs.signatureBytes)),
        operation: .browserAuthenticate(
          origin: inputs.origin, keyProfile: .rsa3072, algorithm: .rsaPkcs1Sha256,
          digest: try Data(hex: inputs.digestSha256))),
      AnswerCase(
        name: "result-completed-batch-signatures",
        result: .signatures(try inputs.batchSignatures.map { try Data(hex: $0) }),
        operation: batch),
    ]
    for testCase in cases {
      let name = testCase.name
      let message = OperationResultMessage.completed(
        operationIdentifier: identifier, result: testCase.result)
      let expected = try Self.expected(corpus, name)
      #expect(try Self.encoded(.operationResult(message)) == expected, "\(name)")
      let received = try Self.received(
        .operationResult, bodyHex: expected, nowMilliseconds: Self.receiptMilliseconds)
      #expect(received == .operationResult(message), "\(name) decodes from the vendored bytes")
      #expect(
        try message.typedResult(for: testCase.operation) == testCase.result,
        "\(name) answers its operation")
    }
  }

  @Test("An identity without a certificate is refused, sent or received")
  internal func identityNeedsACertificate() throws {
    let inputs = try Self.corpus().fixedInputs
    #expect(throws: (any Error).self) {
      _ = try CardIdentity(
        holderName: inputs.holderName, cardIdentifier: inputs.cardIdentifier,
        issuanceDate: inputs.issuanceDate, expirationDate: inputs.expirationDate,
        certificates: [], tokenDisplayName: nil)
    }
    let received = ResultResponse(fields: [
      "card_holder_name": .text(inputs.holderName),
      "card_id": .text(inputs.cardIdentifier),
      "issuance_date": .text(inputs.issuanceDate),
      "expiration_date": .text(inputs.expirationDate),
      "certificates": .array([]),
    ])
    #expect(throws: (any Error).self) { _ = try received.typed(for: .readIdentity) }
  }

  @Test("An inspection answers with the answer to reset alone")
  internal func inspectionCarriesTheAnswerToResetAlone() throws {
    let answerToReset = try Data(hex: try Self.corpus().fixedInputs.answerToReset)
    let sent = ResultResponse(.inspection(answerToReset: answerToReset))
    #expect(sent.fields == ["atr": .bytes(answerToReset)])
    #expect(try sent.typed(for: .inspectCard) == .inspection(answerToReset: answerToReset))
    var withProfiles = sent.fields
    withProfiles["supported_profiles"] = .array(ProfileName.allCases.map { .text($0.rawValue) })
    #expect(throws: CardOperationError.unexpectedField) {
      _ = try ResultResponse(fields: withProfiles).typed(for: .inspectCard)
    }
  }

  @Test("Every registered failure matches byte for byte and decodes back")
  internal func failureResultBodies() throws {
    let corpus = try Self.corpus()
    let identifier = try RappOperationIdentifier(hex: corpus.fixedInputs.operationIdentifierResult)
    let cases: [(String, OperationResultMessage)] = [
      (
        "result-rejected-user-cancelled",
        .failure(operationIdentifier: identifier, failure: .userDenied)
      ),
      (
        "result-cancelled-operation-expired",
        .failure(operationIdentifier: identifier, failure: .requestExpired)
      ),
      (
        "result-rejected-card-error", .failure(operationIdentifier: identifier, failure: .cardError)
      ),
      (
        "result-rejected-unsupported-parameter",
        .failure(operationIdentifier: identifier, failure: .requestInvalidOrUnsupported)
      ),
      (
        "result-rejected-invalid-lifetime",
        .rejection(operationIdentifier: identifier, status: .rejected, error: .invalidLifetime)
      ),
      (
        "result-rejected-unauthorized",
        .failure(operationIdentifier: identifier, failure: .unauthorized)
      ),
      (
        "result-rejected-retry-floor",
        .failure(operationIdentifier: identifier, failure: .retryFloor)
      ),
      (
        "result-rejected-operation-failed",
        .failure(operationIdentifier: identifier, failure: .operationFailed)
      ),
    ]
    for (name, message) in cases {
      let expected = try Self.expected(corpus, name)
      #expect(try Self.encoded(.operationResult(message)) == expected, "\(name)")
      let received = try Self.received(
        .operationResult, bodyHex: expected, nowMilliseconds: Self.receiptMilliseconds)
      #expect(received == .operationResult(message), "\(name) decodes from the vendored bytes")
    }
  }

  @Test("Every protocol error matches byte for byte and decodes by name")
  internal func errorBodies() throws {
    let corpus = try Self.corpus()
    let identifier = try RappOperationIdentifier(hex: corpus.fixedInputs.operationIdentifierError)
    let cases: [(String, ProtocolErrorMessage)] = [
      ("error-busy", .busy(identifier)),
      ("error-duplicate-operation", .duplicate(identifier)),
      (
        "error-operation-failed-bare",
        ProtocolErrorMessage(error: .operationFailed, operationIdentifier: nil)
      ),
    ]
    for (name, error) in cases {
      let expected = try Self.expected(corpus, name)
      #expect(try Self.encoded(.error(error)) == expected, "\(name)")
      #expect(
        corpus.fixedInputs.errorMessages[error.error.rawValue] == error.message,
        "\(name) carries the vendored message")
      let received = try Self.received(
        .error, bodyHex: expected, nowMilliseconds: Self.receiptMilliseconds)
      #expect(received == .error(error), "\(name) decodes by name")
    }
  }

  @Test("Every progress event matches byte for byte")
  internal func progressBodies() throws {
    let corpus = try Self.corpus()
    let identifier = try RappOperationIdentifier(hex: corpus.fixedInputs.operationIdentifierResult)
    let cases: [(String, ProgressEvent)] = [
      ("progress-queued", .queued),
      ("progress-consent-shown", .consentShown),
      ("progress-waiting-for-card", .waitingForCard),
      ("progress-card-wait-ended", .cardWaitEnded),
    ]
    for (name, event) in cases {
      let message = TypedMessage.operationProgress(
        OperationProgressMessage(operationIdentifier: identifier, event: event))
      let expected = try Self.expected(corpus, name)
      #expect(try Self.encoded(message) == expected, "\(name)")
      #expect(
        try Self.received(
          .operationProgress, bodyHex: expected, nowMilliseconds: Self.receiptMilliseconds)
          == message)
    }
  }

  @Test("Card status names the certificate's fingerprint or the zero fingerprint")
  internal func cardStatusBodies() throws {
    let corpus = try Self.corpus()
    let certificate = try Data(hex: corpus.fixedInputs.certificateDer)
    let fingerprint = try #require(RappCertificateFingerprint(certificate: certificate))
    #expect(fingerprint.digest == Data(SHA256.hash(data: certificate)))
    #expect(
      RappCertificateFingerprint(certificate: Data()) == nil, "an empty certificate names none")
    let present = TypedMessage.cardStatus(.present(fingerprint))
    let cases: [(String, TypedMessage)] = [
      ("card-status-present", present),
      ("card-status-absent", .cardStatus(.absent)),
    ]
    for (name, message) in cases {
      let expected = try Self.expected(corpus, name)
      #expect(try Self.encoded(message) == expected, "\(name)")
      #expect(
        try Self.received(.cardStatus, bodyHex: expected, nowMilliseconds: Self.receiptMilliseconds)
          == message)
    }
  }
}
