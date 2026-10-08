// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// A denial's shape on the wire, and the formal tables behind the outcomes.
@Suite("RAPP denial and outcome tables")
internal struct EngineOutcomeTests {
  @Test("A denial ends the operation without closing the session")
  internal func denialIsTerminalAndSessionSurvives() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    let requestMessage = try requester.begin(request, store: &store)
    _ = try proxy.receive(
      requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    try proxy.prerequisitesComplete(operationIdentifier: identifier)

    let denial = try proxy.finishFailure(
      operationIdentifier: identifier, failure: .userDenied, store: &store)
    guard case .sendFailure(let deniedMessage, let closesOnDenial) = denial else {
      EngineReport.check(false, "a denial produces a failure result")
      return
    }
    EngineReport.check(!closesOnDenial, "a denial does not close the session")
    let denied = try requester.receive(deniedMessage, store: &store)
    EngineReport.check(
      denied
        == .terminal(
          operationIdentifier: identifier, state: .rejected, status: .rejected,
          error: .userCancelled),
      "the requester journals the denial as terminal, naming why it ended")
  }

  @Test("The tables end a rejected credential and keep INV-18")
  internal func credentialRejectionAndIntegrityTables() {
    var model = RappState(role: .proxy)
    model.pairing = .pairedConnected
    model.session = .healthy
    model.operation = .executing
    let outcome = model.credentialRejected()
    EngineReport.check(
      model.operation == .credentialRejected,
      "the tables end a credential-rejected operation")
    EngineReport.check(
      model.session != .healthy, "the tables close the session on a rejected credential")
    EngineReport.check(
      model.requiresUserIntent, "a rejected credential requires fresh user intent")
    EngineReport.check(!outcome.actions.isEmpty, "the credential rejection emits actions")

    var ambiguous = RappState(role: .requester)
    ambiguous.pairing = .pairedConnected
    ambiguous.session = .healthy
    ambiguous.operation = .committed
    _ = ambiguous.sessionIntegrityFailed()
    EngineReport.check(
      ambiguous.operation == .ambiguous,
      "a session lost after commit leaves the operation ambiguous")
    EngineReport.check(
      ambiguous.pairing == .pairedConnected,
      "an unattributable loss keeps the pairing, per INV-18")
  }
}
