// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP operation progress signaling")
internal struct EngineProgressTests {
  @Test("Advisory progress signals waiting_for_card and card_wait_ended")
  internal func progressSignaling() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier

    let requestMessage = try requester.begin(request, store: &store)
    _ = try proxy.receive(
      requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)

    let waitingMsg = try proxy.reportProgress(
      operationIdentifier: identifier, event: .waitingForCard)
    guard case .operationProgress(let waitingProgress) = waitingMsg else {
      #expect(Bool(false), "expected operationProgress message")
      return
    }
    #expect(waitingProgress.event == .waitingForCard)
    #expect(waitingProgress.reference.operationIdentifier == identifier)

    let requesterDispatch1 = try requester.receive(waitingMsg, store: &store)
    #expect(
      requesterDispatch1 == .progress(operationIdentifier: identifier, event: .waitingForCard))
    #expect(requester.liveOperationStates == [identifier: .requested])

    let endedMsg = try proxy.reportProgress(operationIdentifier: identifier, event: .cardWaitEnded)
    let requesterDispatch2 = try requester.receive(endedMsg, store: &store)
    #expect(requesterDispatch2 == .progress(operationIdentifier: identifier, event: .cardWaitEnded))
    #expect(requester.liveOperationStates == [identifier: .requested])

    var proxyRefused = false
    do {
      _ = try proxy.receive(
        waitingMsg, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    } catch EngineError.authenticatedProtocolViolation(.illegalMessageForActiveOperation) {
      proxyRefused = true
    }
    #expect(proxyRefused, "proxy refuses operationProgress from peer")
  }
}
