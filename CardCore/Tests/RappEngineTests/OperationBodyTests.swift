// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Replays the operation-protocol bodies an independent encoder produced from
// the RAPP v26.10.22 schemas. Every body is produced through the engine's own
// encoders rather than assembled here, so the test proves what a peer would
// actually receive, and every body is read back through the decoder a peer
// runs.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP operation bodies against the vendored bytes")
internal struct OperationBodyTests {
  /// One typed request and the vector it must reproduce.
  private struct RequestCase {
    let name: String
    let operation: CardOperation
  }

  /// The session identifier the read-back envelopes carry.
  private static let sessionIdentifier = Data(count: WireLimits.sessionIdentifier)

  /// The sequence of the first envelope in a direction (RAPP v26.10.22
  /// §7.2 item 3).
  internal static let firstSequence: UInt64 = 0

  /// When a read-back body arrives, on the receiver's continuous clock;
  /// only a request records it.
  internal static let receiptMilliseconds: UInt64 = 0

  /// The vector rows for one corpus file.
  internal static func corpus() throws -> OperationCorpus {
    try CorpusFile.operation(filePath: #filePath)
  }

  internal static func expected(_ corpus: OperationCorpus, _ name: String) throws -> String {
    guard let vector = corpus.vectors.first(where: { $0.name == name }) else {
      throw CorpusError.missingHandshake(name: name)
    }
    return vector.bodyHex
  }

  internal static func encoded(_ message: TypedMessage) throws -> String {
    guard let body = message.wireBody() else {
      throw CorpusError.missingHandshake(name: "encodable body")
    }
    return try WireValue.map(body).encoded().hex
  }

  /// The registered message type a corpus row names.
  private static func messageType(_ corpusName: String) throws -> MessageType {
    let names: [String: MessageType] = [
      "OperationRequest": .operationRequest,
      "OperationResult": .operationResult,
      "OperationProgress": .operationProgress,
      "Error": .error,
      "CardStatus": .cardStatus,
      "PairingStored": .pairingStored,
    ]
    guard let type = names[corpusName] else {
      throw CorpusError.missingHandshake(name: corpusName)
    }
    return type
  }

  /// Reads `bodyHex` the way a receiver does: as the body of an envelope of
  /// `type`, schema-checked and then typed.
  internal static func received(
    _ type: MessageType, bodyHex: String, nowMilliseconds: UInt64
  ) throws -> TypedMessage {
    guard case .map(let body) = try decodeDeterministicCbor(try Data(hex: bodyHex)) else {
      throw CorpusError.notAMap(bodyHex)
    }
    let envelope = try Envelope.decode(
      try Envelope(
        messageType: type, sessionIdentifier: sessionIdentifier, sequence: firstSequence, body: body
      )
      .encoded())
    if type == .pairingStored {
      _ = try PairingStored.from(body: envelope.body)
    }
    return try SessionMessageCodec.message(from: envelope, nowMilliseconds: nowMilliseconds)
  }

  internal static func request(
    _ inputs: OperationInputs, _ operation: CardOperation
  ) throws -> OperationRequest {
    try OperationRequest(
      operationIdentifier: try RappOperationIdentifier(hex: inputs.operationIdentifierRequest),
      profile: operation.requiredProfile,
      localStartMilliseconds: inputs.localStartMilliseconds,
      expiresAfterMilliseconds: inputs.expiresAfterMilliseconds,
      operation: operation)
  }

  @Test("The vendored bodies are the current revision")
  internal func vectorIdentity() throws {
    let corpus = try Self.corpus()
    #expect(corpus.format == "fi.refineid.rapp.operation-vectors")
    #expect(corpus.protocolDocumentVersion == "26.10.22")
    #expect(!corpus.vectors.isEmpty)
    #expect(!corpus.rejected.isEmpty)
  }

  @Test("Every typed request matches byte for byte and parses back")
  internal func requestBodies() throws {
    let corpus = try Self.corpus()
    let inputs = corpus.fixedInputs
    let cases: [RequestCase] = [
      RequestCase(name: "request-inspect-card", operation: .inspectCard),
      RequestCase(name: "request-read-identity", operation: .readIdentity),
      RequestCase(
        name: "request-read-certificate-authentication",
        operation: .readCertificate(kind: .authentication)),
      RequestCase(
        name: "request-read-certificate-signature", operation: .readCertificate(kind: .signature)),
      RequestCase(
        name: "request-browser-authenticate",
        operation: .browserAuthenticate(
          origin: inputs.origin, keyProfile: .rsa3072, algorithm: .rsaPkcs1Sha256,
          digest: try Data(hex: inputs.digestSha256))),
      RequestCase(
        name: "request-sign-document",
        operation: .signDocument(
          documentName: inputs.documentName, keyProfile: .ecdsaP384, algorithm: .ecdsaSha384,
          digest: try Data(hex: inputs.digestSha384))),
      RequestCase(
        name: "request-batch-sign-documents",
        operation: .batchSignDocuments(
          documentNames: inputs.batchDocumentNames, keyProfile: .ecdsaP256,
          algorithm: .ecdsaSha256,
          digests: try inputs.batchDigestsSha256.map { try Data(hex: $0) })),
    ]
    for testCase in cases {
      let request = try Self.request(inputs, testCase.operation)
      let expected = try Self.expected(corpus, testCase.name)
      #expect(try Self.encoded(.operationRequest(request)) == expected, "\(testCase.name)")
      let parsed = try Self.received(
        .operationRequest, bodyHex: expected, nowMilliseconds: inputs.localStartMilliseconds)
      #expect(parsed == .operationRequest(request), "\(testCase.name) parses back")
    }
  }

  @Test("The storage confirmation matches byte for byte")
  internal func pairingStoredBody() throws {
    let corpus = try Self.corpus()
    let stored = PairingStored(pairIdentifier: try Data(hex: corpus.fixedInputs.pairIdentifier))
    let expected = try Self.expected(corpus, "pairing-stored")
    #expect(try WireValue.map(stored.body()).encoded().hex == expected)
    _ = try Self.received(
      .pairingStored, bodyHex: expected, nowMilliseconds: Self.receiptMilliseconds)
  }

  @Test("Every vendored body is covered by an encoding check above")
  internal func everyVectorIsCovered() throws {
    let corpus = try Self.corpus()
    for vector in corpus.vectors {
      let type = try Self.messageType(vector.messageType)
      _ = try Self.received(
        type, bodyHex: vector.bodyHex, nowMilliseconds: Self.receiptMilliseconds)
    }
  }

  @Test("Every rejected body is refused by the receiver")
  internal func rejectedBodies() throws {
    let corpus = try Self.corpus()
    for vector in corpus.rejected {
      let type = try Self.messageType(vector.messageType)
      #expect(throws: (any Error).self, "\(vector.name)") {
        _ = try Self.received(
          type, bodyHex: vector.bodyHex, nowMilliseconds: Self.receiptMilliseconds)
      }
    }
  }

  @Test("A changed digest changes the request bytes")
  internal func changedDigestChangesTheBytes() throws {
    let corpus = try Self.corpus()
    let inputs = corpus.fixedInputs
    var digest = try Data(hex: inputs.digestSha256)
    let first = try #require(digest.indices.first)
    digest[first] ^= 1
    let altered = TypedMessage.operationRequest(
      try Self.request(
        inputs,
        .browserAuthenticate(
          origin: inputs.origin, keyProfile: .rsa3072, algorithm: .rsaPkcs1Sha256,
          digest: digest)))
    #expect(
      try Self.encoded(altered) != (try Self.expected(corpus, "request-browser-authenticate")))
  }
}
