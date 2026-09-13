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

  @Test("Progress reporting fails on unknown operation")
  internal func progressUnknownOperation() throws {
    let proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let unknownID = Data(repeating: 0x99, count: 16)
    var failedAsExpected = false
    do {
      _ = try proxy.reportProgress(operationIdentifier: unknownID, event: .waitingForCard)
    } catch EngineError.unknownLocalOperation {
      failedAsExpected = true
    }
    #expect(failedAsExpected)
  }

  @Test("Progress reporting fails on terminal operation")
  internal func progressTerminalOperation() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier

    _ = try proxy.receive(
      .operationRequest(request), store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)

    _ = try proxy.finishFailure(operationIdentifier: identifier, error: .userDenied, store: &store)

    var failedAsExpected = false
    do {
      _ = try proxy.reportProgress(operationIdentifier: identifier, event: .waitingForCard)
    } catch EngineError.invalidLocalTransition {
      failedAsExpected = true
    }
    #expect(failedAsExpected)
  }

  @Test("Requester silently ignores progress message with mismatched reference")
  internal func progressReferenceMismatch() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    _ = try requester.begin(request, store: &store)

    let mismatchedRef = OperationReference(
      operationIdentifier: identifier,
      requestHash: Data(repeating: 0xee, count: 32)
    )
    let badMsg = TypedMessage.operationProgress(
      OperationProgressMessage(reference: mismatchedRef, event: .waitingForCard)
    )

    let dispatch = try requester.receive(badMsg, store: &store)
    #expect(dispatch == .ignoredProgress(operationIdentifier: identifier))
  }

  @Test("Requester silently ignores progress message on terminal or completed operation")
  internal func progressIgnoredOnTerminalOperation() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    _ = try requester.begin(request, store: &store)
    _ = try requester.cancel(operationIdentifier: identifier, reason: nil, store: &store)

    let reference = OperationReference(
      operationIdentifier: identifier,
      requestHash: try request.requestHash()
    )
    let progressMsg = TypedMessage.operationProgress(
      OperationProgressMessage(reference: reference, event: .waitingForCard)
    )
    let dispatch = try requester.receive(progressMsg, store: &store)
    #expect(dispatch == .ignoredProgress(operationIdentifier: identifier))
  }

  @Test("Requester silently ignores progress message on unknown operation")
  internal func progressIgnoredOnUnknownOperation() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let unknownID = Data(repeating: 0x88, count: 16)
    let reference = OperationReference(
      operationIdentifier: unknownID,
      requestHash: Data(repeating: 0x99, count: 32)
    )
    let progressMsg = TypedMessage.operationProgress(
      OperationProgressMessage(reference: reference, event: .waitingForCard)
    )
    let dispatch = try requester.receive(progressMsg, store: &store)
    #expect(dispatch == .ignoredProgress(operationIdentifier: unknownID))
  }

  @Test("Unknown progress event decodes cleanly and is ignored as no-op")
  internal func progressUnknownEventIgnored() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    _ = try requester.begin(request, store: &store)

    let reference = OperationReference(
      operationIdentifier: identifier,
      requestHash: try request.requestHash()
    )
    let unknownEventMsg = TypedMessage.operationProgress(
      OperationProgressMessage(
        reference: reference,
        event: ProgressEvent(wireValue: "future_event")
      )
    )

    #expect(ProgressEvent(wireValue: "future_event") == .unknown)

    let dispatch = try requester.receive(unknownEventMsg, store: &store)
    #expect(dispatch == .ignoredProgress(operationIdentifier: identifier))
  }

  @Test("Envelope decodes unknown future progress event without error")
  internal func envelopeDecodesFutureProgressEvent() throws {
    let identifier = Data(repeating: 0x42, count: 16)
    let requestHash = Data(repeating: 0x53, count: 32)
    let envelope = Envelope(
      messageType: .operationProgress,
      sessionIdentifier: Data(repeating: 0x01, count: 16),
      sequence: 1,
      body: [
        "operation_id": .bytes(identifier),
        "request_hash": .bytes(requestHash),
        "event": .text("device_pin_requested_future"),
      ],
      critical: [],
      extensions: [:]
    )
    let encoded = try envelope.encoded()
    let decoded = try Envelope.decode(encoded)
    #expect(decoded.messageType == .operationProgress)
    let progress = try OperationProgressMessage.from(wireBody: decoded.body)
    #expect(progress.event == .unknown)
    #expect(progress.reference.operationIdentifier == identifier)
  }
}
