// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP batch operation bodies against the vendored bytes")
internal struct BatchBodyTests {
  private static func expected(_ corpus: OperationCorpus, _ name: String) throws -> String {
    guard let vector = corpus.vectors.first(where: { $0.name == name }) else {
      throw CorpusError.missingHandshake(name: name)
    }
    return vector.bodyHex
  }

  private static func encoded(_ message: TypedMessage) throws -> String {
    guard let body = try message.encodedBody() else {
      throw CorpusError.missingHandshake(name: "encodable body")
    }
    return body.hex
  }

  @Test("The batch request and both batch results match byte for byte")
  internal func batchBodies() throws {
    let corpus = try CorpusFile.operation(filePath: #filePath)
    let inputs = corpus.fixedInputs
    let operation = CardOperation.batchSignDocuments(
      documentNames: inputs.batchDocumentNames, keyProfile: .ecdsaP256,
      algorithm: .ecdsaSha256, digests: try inputs.batchDigestsSha256.map { try Data(hex: $0) })
    let request = try OperationRequest(
      operationIdentifier: try Data(hex: inputs.operationIdentifierRequest),
      pairIdentifier: try Data(hex: inputs.pairIdentifier),
      sessionIdentifier: try Data(hex: inputs.sessionIdentifier),
      profile: .documentSigning,
      localStartMilliseconds: inputs.localStartMilliseconds,
      expiresAfterMilliseconds: inputs.expiresAfterMilliseconds,
      operation: operation)
    #expect(
      try Self.encoded(.operationRequest(request))
        == (try Self.expected(corpus, "request-batch-sign-documents")))
    let vector = try #require(corpus.vectors.first { $0.name == "request-batch-sign-documents" })
    #expect(try request.requestHash().hex == vector.requestHashHex)

    let reference = OperationReference(
      operationIdentifier: try Data(hex: inputs.operationIdentifierReference),
      requestHash: try Data(hex: inputs.requestHashReference))
    let signatures = try inputs.batchSignatures.map { try Data(hex: $0) }
    let completed = OperationResultMessage.completed(
      reference: reference, result: .signatures(signatures))
    #expect(
      try Self.encoded(.operationResult(completed))
        == (try Self.expected(corpus, "result-completed-batch-signatures")))
    #expect(try completed.typedResult(for: operation) == .signatures(signatures))

    let partial = OperationResultMessage.failure(
      reference: reference, failure: .cardCompletionAmbiguous,
      batchSignatures: Array(signatures.prefix(1)))
    #expect(
      try Self.encoded(.operationResult(partial))
        == (try Self.expected(corpus, "result-ambiguous-batch-partial")))
    let decoded = try OperationResultMessage.decode(
      try Data(hex: try Self.expected(corpus, "result-ambiguous-batch-partial")))
    #expect(try decoded.partialSignatures(for: operation) == Array(signatures.prefix(1)))
  }
}
