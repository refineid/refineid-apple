// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// A result acknowledgement that arrives twice, or for nothing, changes
/// nothing (RAPP v26.10.18 §8.2 item 5).
@Suite("RAPP duplicate acknowledgements")
internal struct DuplicateAcknowledgementTests {
  @Test("A second acknowledgement of a denial is not an operation message")
  internal func duplicateDenialAcknowledgementIsIgnored() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    let reference = OperationReference(
      operationIdentifier: identifier, requestHash: try request.requestHash())
    let requestMessage = try requester.begin(request, store: &store)
    _ = try proxy.receive(
      requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    try proxy.prerequisitesComplete(operationIdentifier: identifier)
    _ = try proxy.finishFailure(
      operationIdentifier: identifier, failure: .userDenied, store: &store)

    let first = try proxy.receive(
      .operationResultAck(reference), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    #expect(first == .resultAcknowledged(operationIdentifier: identifier))
    let second = try proxy.receive(
      .operationResultAck(reference), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    #expect(second == .notOperation(.operationResultAck(reference)))
  }

  @Test("An acknowledgement for an operation never seen is not an operation message")
  internal func strayAcknowledgementIsIgnored() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let reference = OperationReference(
      operationIdentifier: request.operationIdentifier, requestHash: try request.requestHash())
    let stray = try proxy.receive(
      .operationResultAck(reference), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    #expect(stray == .notOperation(.operationResultAck(reference)))
  }
}
