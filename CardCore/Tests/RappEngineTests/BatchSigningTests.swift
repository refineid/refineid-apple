// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.1 batch_sign_documents (section 9.3)")
internal struct BatchSigningTests {
  private static let names = ["Contract.pdf", "Annex.pdf", "Terms.pdf"]
  private static let digests = (1...3).map { index in
    Data(repeating: UInt8(index), count: DigestLength.sha256)
  }
  private static let signatures = (1...3).map { index in
    Data(repeating: UInt8(0xA0 + index), count: OperationFill.signatureLength)
  }
  /// One more document than section 9.3 admits.
  private static let tooManyDocuments = 65

  private static func operation(
    names: [String] = names, digests: [Data] = digests
  ) -> CardOperation {
    .batchSignDocuments(
      documentNames: names, keyProfile: .ecdsaP256, algorithm: .ecdsaSha256, digests: digests)
  }

  private static func request(_ operation: CardOperation = operation()) throws -> OperationRequest {
    try fixedRequest(profile: .documentSigning, operation: operation)
  }

  /// A proxy engine with the batch approved and its first command durable.
  private static func approvedEngine(
    _ store: inout MemoryJournalStore
  ) throws -> ProxyOperationEngine {
    var engine = ProxyOperationEngine(grantedProfiles: [.documentSigning], recovered: [])
    let request = try Self.request()
    let admitted = try engine.receive(
      .operationRequest(request), store: &store,
      nowMilliseconds: OperationFixture.startMilliseconds,
      maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
    #expect(admitted == .inspectPrerequisites(operationIdentifier: request.operationIdentifier))
    try engine.prerequisitesComplete(operationIdentifier: request.operationIdentifier)
    let approved = try engine.approve(
      operationIdentifier: request.operationIdentifier,
      approval: try UserApproval(
        for: request, approvedAtMilliseconds: OperationFixture.approvalMilliseconds),
      store: &store, nowMilliseconds: OperationFixture.approvalMilliseconds,
      maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
    #expect(approved == .beginCardCommand(operationIdentifier: request.operationIdentifier))
    return engine
  }

  @Test("A batch request round-trips through its wire body and hash")
  internal func requestRoundTrip() throws {
    let request = try Self.request()
    #expect(request.operation.isConsequential)
    #expect(request.operation.requiredProfile == .documentSigning)
    let parsed = try OperationRequest.from(
      wireBody: request.wireBody(),
      pairIdentifier: OperationFixture.pairIdentifier,
      sessionIdentifier: OperationFixture.sessionIdentifier,
      localStartMilliseconds: OperationFixture.startMilliseconds)
    #expect(parsed == request)
    #expect(try parsed.requestHash() == request.requestHash())
  }

  @Test("Batch size, pairing of names and digests, and name length are bounded")
  internal func batchBounds() {
    let invalid: [CardOperation] = [
      Self.operation(names: [], digests: []),
      Self.operation(names: Array(Self.names.prefix(2))),
      Self.operation(
        names: Array(repeating: "Doc.pdf", count: Self.tooManyDocuments),
        digests: Array(repeating: Self.digests[0], count: Self.tooManyDocuments)),
      Self.operation(
        names: [String(repeating: "x", count: 257)], digests: [Self.digests[0]]),
      Self.operation(names: [Self.names[0]], digests: [Data(count: DigestLength.sha256 - 1)]),
    ]
    for operation in invalid {
      #expect(throws: (any Error).self) { try operation.validate() }
    }
  }

  @Test("Each signature is journaled before the next, and completion delivers them in order")
  internal func completesFromTheJournal() throws {
    var store = MemoryJournalStore()
    var engine = try Self.approvedEngine(&store)
    let identifier = OperationFixture.operationIdentifier
    #expect(store.proxyWrites.last?.batch == .init(total: 3, completedSignatures: []))
    #expect(throws: (any Error).self) {
      try engine.completeBatch(operationIdentifier: identifier, store: &store)
    }
    for signature in Self.signatures {
      try engine.recordBatchSignature(
        operationIdentifier: identifier, signature: signature, store: &store)
      #expect(store.proxyWrites.last?.batch?.completedSignatures.last == signature)
    }
    #expect(throws: (any Error).self) {
      try engine.recordBatchSignature(
        operationIdentifier: identifier, signature: Self.signatures[0], store: &store)
    }
    guard
      case .send(.operationResult(let result)) = try engine.completeBatch(
        operationIdentifier: identifier, store: &store)
    else {
      Issue.record("a completed batch sends its result")
      return
    }
    #expect(try result.typedResult(for: Self.operation()) == .signatures(Self.signatures))
    // One write starts the command; each later one records a signature.
    let starts = store.proxyWrites.filter { record in
      record.state == .executing && record.batch?.completedSignatures.isEmpty == true
    }
    #expect(starts.count == 1)
  }

  @Test("An interrupted batch is ambiguous and carries the signatures already made")
  internal func interruptedBatchCarriesPartialProgress() throws {
    var store = MemoryJournalStore()
    var engine = try Self.approvedEngine(&store)
    let identifier = OperationFixture.operationIdentifier
    try engine.recordBatchSignature(
      operationIdentifier: identifier, signature: Self.signatures[0], store: &store)
    guard
      case .sendFailure(.operationResult(let result), _) = try engine.finishFailure(
        operationIdentifier: identifier, failure: .cardCompletionAmbiguous, store: &store)
    else {
      Issue.record("an ambiguous batch sends its result")
      return
    }
    #expect(result.status == .ambiguous)
    #expect(try result.partialSignatures(for: Self.operation()) == [Self.signatures[0]])
    #expect(result.response?.fields["completed_count"] == .unsigned(1))

    var requester = try RequesterOperation(request: try Self.request())
    var requesterStore = MemoryJournalStore()
    _ = try requester.begin(to: &requesterStore)
    let action = try requester.receiveResult(
      try OperationResultMessage.decode(try result.encoded()), to: &requesterStore)
    #expect(
      action
        == .terminal(
          state: .ambiguous, status: .ambiguous, error: .cardError,
          batchSignatures: [Self.signatures[0]]))
  }

  @Test("A partial response on anything but an ambiguous batch is refused")
  internal func partialProgressOnlyForBatches() throws {
    let reference = OperationReference(
      operationIdentifier: OperationFixture.operationIdentifier,
      requestHash: try browserRequest().requestHash())
    let forged = OperationResultMessage.failure(
      reference: reference, failure: .cardCompletionAmbiguous,
      batchSignatures: [Self.signatures[0]])
    #expect(throws: (any Error).self) {
      try forged.validate(for: reference, operation: try browserRequest().operation)
    }
  }

  @Test("Recovery keeps the batch progress and answers with it, never re-signing")
  internal func recoveredBatchAnswersWithProgress() throws {
    var store = MemoryJournalStore()
    var engine = try Self.approvedEngine(&store)
    let identifier = OperationFixture.operationIdentifier
    try engine.recordBatchSignature(
      operationIdentifier: identifier, signature: Self.signatures[0], store: &store)
    try engine.recordBatchSignature(
      operationIdentifier: identifier, signature: Self.signatures[1], store: &store)
    let interrupted = try #require(store.proxyWrites.last)
    let stored = try ProxyJournalRecord.decode(try interrupted.encoded())
    #expect(stored == interrupted)

    var journal = OperationJournal(recovered: stored)
    var recoveryStore = MemoryJournalStore()
    try journal.recoverAfterCrash(to: &recoveryStore)
    var restarted = ProxyOperationEngine(
      grantedProfiles: [.documentSigning],
      recovered: [RecoveredProxyRecord(record: journal.record, retainedResult: nil)])
    let answer = try restarted.receive(
      .operationRequest(try Self.request()), store: &recoveryStore,
      nowMilliseconds: OperationFixture.startMilliseconds,
      maximumLifetimeMilliseconds: OperationFixture.maximumLifetimeMilliseconds)
    guard case .send(.operationResult(let result)) = answer else {
      Issue.record("a retransmission is answered from the journal")
      return
    }
    #expect(result.status == .ambiguous)
    #expect(
      try result.partialSignatures(for: Self.operation()) == Array(Self.signatures.prefix(2)))
    #expect(recoveryStore.transmissionsRecorded == 0)
  }

  @Test("A record without a batch encodes exactly as before")
  internal func plainRecordsCarryNoBatchKey() throws {
    var transaction = try AuthorizationTransaction(request: try browserRequest())
    var journalStore = OperationJournalStore()
    try executeToCard(&transaction, &journalStore)
    let record = try #require(journalStore.writes.last)
    #expect(record.batch == nil)
    #expect(try decodedMap(try record.encoded())["batch"] == nil)
  }
}
