// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Both engines answer each other over an in-memory channel

import Foundation
import Testing

@testable import RappEngine

// Each drive runs as one continuous sequence, because that is what it
// proves: each step depends on the state the previous one left, and a peer
// answers a real predecessor rather than a fixture.
@Suite("RAPP proxy and requester engines")
internal struct EngineDriveTests {
  private static func receive(
    _ proxy: inout ProxyOperationEngine,
    _ message: TypedMessage,
    _ store: inout MemoryJournalStore,
    now: UInt64 = EngineFixture.nowMilliseconds
  ) throws -> ProxyDispatch {
    try proxy.receive(
      message, store: &store, nowMilliseconds: now,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  }

  private static func approve(
    _ proxy: inout ProxyOperationEngine,
    _ request: OperationRequest,
    _ store: inout MemoryJournalStore,
    at now: UInt64 = EngineFixture.nowMilliseconds
  ) throws -> ProxyDispatch {
    try proxy.prerequisitesComplete(operationIdentifier: request.operationIdentifier)
    let approval = try UserApproval(for: request, approvedAtMilliseconds: now)
    return try proxy.approve(
      operationIdentifier: request.operationIdentifier, approval: approval, store: &store,
      nowMilliseconds: now,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  }

  @Test("One operation completes end to end, transmitting exactly once")
  internal func happyPathCompletes() throws {
    let happy = try driveHappyPath()
    // Proving the at-most-once check is real: counting every journal write
    // as a transmission would let the happy path look like two.
    EngineReport.check(
      happy.store.proxyWrites.count > 1 && happy.store.transmissionsRecorded == 1,
      "several journal writes occurred but exactly one was a transmission")
  }

  @Test("A second request while one is live is refused without changing state")
  internal func secondRequestIsRefused() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(
      grantedProfiles: [.authentication, .cardStatus], recovered: [])
    let first = try engineRequest(operation: signingOperation())
    _ = try Self.receive(&proxy, .operationRequest(first), &store)
    let statesBefore = proxy.liveOperationStates
    let second = try engineRequest(
      operation: .inspectCard, operationIdentifier: EngineFixture.secondOperationIdentifier)
    let refusal = try Self.receive(&proxy, .operationRequest(second), &store)
    EngineReport.check(
      refusal
        == .send(
          .error(.operationFailed(operationIdentifier: EngineFixture.secondOperationIdentifier))),
      "a second request is refused with operation_failed")
    EngineReport.check(
      proxy.liveOperationStates == statesBefore, "the refusal changed no operation state")
  }

  @Test("An ungranted profile is answered as unauthorized, touching no card")
  internal func ungrantedProfileIsUnauthorized() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.cardStatus], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let answer = try Self.receive(&proxy, .operationRequest(request), &store)
    guard case .sendFailure(.operationResult(let result), let closes) = answer else {
      EngineReport.check(false, "an ungranted profile is answered with a result")
      return
    }
    EngineReport.check(
      result.status == .rejected && result.error == .unauthorized,
      "the result is rejected as unauthorized (section 8.2.3)")
    EngineReport.check(!closes, "the session stays open")
    EngineReport.check(store.transmissionsRecorded == 0, "no card command was possible")
  }

  @Test("An unsupported parameter is a semantic rejection, not a violation")
  internal func unsupportedParameterIsRejected() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let refusal = OperationRequestRefusal(
      reference: try OperationReference(of: request), error: .unsupportedParameter)
    let answer = try Self.receive(&proxy, .operationRequestRefused(refusal), &store)
    guard case .send(.operationResult(let result)) = answer else {
      EngineReport.check(false, "an unsupported request is answered with a result")
      return
    }
    EngineReport.check(
      result.status == .rejected && result.error == .unsupportedParameter,
      "the result names unsupported_parameter")
  }

  @Test("Identical retransmissions join or replay; altered ones are duplicates")
  internal func retransmissionsAreIdempotent() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    _ = try Self.receive(&proxy, .operationRequest(request), &store)

    let joined = try Self.receive(&proxy, .operationRequest(request), &store)
    EngineReport.check(
      joined == .ignoredDuplicate(operationIdentifier: identifier),
      "an identical retransmission awaiting consent joins it")

    let altered = try engineRequest(
      operation: .browserAuthenticate(
        origin: "https://other.test", keyProfile: .rsa3072, algorithm: .rsaPkcs1Sha256,
        digest: EngineFixture.digest))
    let collision = try Self.receive(&proxy, .operationRequest(altered), &store)
    EngineReport.check(
      collision == .send(.error(.duplicateOperation(operationIdentifier: identifier))),
      "the same identifier with changed content is a duplicate_operation")

    _ = try Self.approve(&proxy, request, &store)
    let result = OperationResultMessage.completed(
      reference: try OperationReference(of: request), result: .signature(EngineFixture.signature))
    _ = try proxy.finishCompleted(operationIdentifier: identifier, result: result, store: &store)
    let replayed = try Self.receive(&proxy, .operationRequest(request), &store)
    EngineReport.check(
      replayed == .send(.operationResult(result)),
      "a retransmission after completion replays the cached result")

    _ = try Self.receive(
      &proxy, .operationResultAck(try OperationReference(of: request)), &store)
    let retired = try Self.receive(&proxy, .operationRequest(request), &store)
    guard case .send(.operationResult(let tombstone)) = retired else {
      EngineReport.check(false, "a retransmission after retirement is answered")
      return
    }
    EngineReport.check(
      tombstone.retired && tombstone.status == .completed
        && tombstone.error == .operationAlreadyRetired && tombstone.response == nil,
      "a retired operation answers from its tombstone without the card")
    EngineReport.check(
      store.transmissionsRecorded == 1, "no retransmission reached the card again")
  }

  @Test("A status query re-delivers a retained result, and answers from tombstones")
  internal func statusReconciles() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    _ = try Self.receive(&proxy, .operationRequest(request), &store)
    _ = try Self.approve(&proxy, request, &store)
    let result = OperationResultMessage.completed(
      reference: try OperationReference(of: request), result: .signature(EngineFixture.signature))
    _ = try proxy.finishCompleted(operationIdentifier: identifier, result: result, store: &store)

    let pending = try Self.receive(
      &proxy, .operationStatusRequest(operationIdentifier: identifier), &store)
    guard case .sendAll(let messages) = pending, messages.count == 2,
      case .operationStatus(let report) = messages[0]
    else {
      EngineReport.check(false, "a pending result is reported and re-delivered")
      return
    }
    EngineReport.check(
      report.known && !report.retired && report.state?.wireStateName == "completed",
      "the report names a completed, unretired operation")
    EngineReport.check(messages[1] == .operationResult(result), "the result follows the report")

    let unknown = try Self.receive(
      &proxy, .operationStatusRequest(operationIdentifier: EngineFixture.secondOperationIdentifier),
      &store)
    EngineReport.check(
      unknown
        == .send(
          .operationStatus(
            StatusReport(
              operationIdentifier: EngineFixture.secondOperationIdentifier, known: false))),
      "an unknown operation is reported unknown")
  }

  @Test("A mismatched result is a violation; an unknown one is a stale race")
  internal func wrongAndUnknownResults() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    _ = try requester.begin(request, store: &store)
    let reference = try OperationReference(of: request)
    // A certificate answer cannot answer a signing request.
    let wrong = OperationResultMessage.completed(
      reference: reference, result: .certificate(EngineFixture.signature))
    var refused = false
    do {
      _ = try requester.receive(.operationResult(wrong), store: &store)
    } catch EngineError.authenticatedProtocolViolation(.invalidOperationMessage) {
      refused = true
    }
    EngineReport.check(refused, "a result that answers another operation is a violation")

    let foreign = OperationReference(
      operationIdentifier: EngineFixture.secondOperationIdentifier,
      requestHash: reference.requestHash)
    let unknown = try requester.receive(
      .operationResult(
        OperationResultMessage.completed(
          reference: foreign, result: .signature(EngineFixture.signature))),
      store: &store)
    EngineReport.check(
      unknown
        == .ignoredStale(
          operationIdentifier: EngineFixture.secondOperationIdentifier,
          response: .error(
            .unknownOperation(operationIdentifier: EngineFixture.secondOperationIdentifier))),
      "a result for an unknown operation is a stale-reference race")
  }

  @Test("Liveness traffic leaves the in-flight operation untouched")
  internal func livenessLeavesOperationsAlone() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    _ = try Self.receive(&proxy, .operationRequest(request), &store)
    let before = proxy.liveOperationStates[identifier]
    let liveness = try Self.receive(&proxy, .other(.livenessPing), &store)
    EngineReport.check(
      liveness == .notOperation(.other(.livenessPing)),
      "liveness is not an operation message")
    EngineReport.check(
      proxy.liveOperationStates[identifier] == before,
      "liveness left the in-flight operation untouched")
  }

  @Test("A late approval expires instead of authorizing")
  internal func lateApprovalExpires() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    _ = try Self.receive(&proxy, .operationRequest(request), &store)
    let expired = try Self.approve(
      &proxy, request, &store, at: EngineFixture.expiredNowMilliseconds)
    guard case .sendFailure(.operationResult(let expiredResult), _) = expired else {
      EngineReport.check(false, "a late approval answers with an expired result")
      return
    }
    EngineReport.check(
      expiredResult.status == .cancelled && expiredResult.error == .operationExpired,
      "a late approval is cancelled as operation_expired")
    EngineReport.check(store.transmissionsRecorded == 0, "an expired approval transmitted nothing")
  }

  @Test("A failed durable write authorizes no card command")
  internal func failedWriteAuthorizesNothing() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try engineRequest(operation: signingOperation())
    _ = try Self.receive(&proxy, .operationRequest(request), &store)
    store.failNextWrite = true
    var authorized = true
    do {
      _ = try Self.approve(&proxy, request, &store)
    } catch {
      authorized = false
    }
    EngineReport.check(!authorized, "a failed durable write authorizes no card command")
    EngineReport.check(
      store.transmissionsRecorded == 0, "no transmission is recorded when the write failed")
  }
}
