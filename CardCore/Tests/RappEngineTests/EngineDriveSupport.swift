// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// The shared drive: both engines answering each other over an in-memory
// channel, from request to acknowledgement.

import Foundation

@testable import RappEngine

internal func engineRequest(operation: CardOperation) throws -> OperationRequest {
  try engineRequest(operation: operation, operationIdentifier: EngineFixture.operationIdentifier)
}

internal func engineRequest(
  operation: CardOperation,
  operationIdentifier: Data
) throws -> OperationRequest {
  try OperationRequest(
    operationIdentifier: operationIdentifier,
    pairIdentifier: EngineFixture.pairIdentifier,
    sessionIdentifier: EngineFixture.sessionIdentifier,
    profile: operation.requiredProfile,
    localStartMilliseconds: EngineFixture.startMilliseconds,
    expiresAfterMilliseconds: EngineFixture.expiresAfterMilliseconds,
    operation: operation)
}

internal func signingOperation() -> CardOperation {
  .browserAuthenticate(
    origin: EngineFixture.origin,
    keyProfile: .rsa3072,
    algorithm: .rsaPkcs1Sha256,
    digest: EngineFixture.digest)
}

/// Drives one consequential operation from request to the authorized card
/// command; false when a step refused.
private func driveToCardCommand(
  _ proxy: inout ProxyOperationEngine,
  _ requester: inout RequesterOperationEngine,
  _ store: inout MemoryJournalStore,
  request: OperationRequest
) throws -> Bool {
  let identifier = request.operationIdentifier
  let requestMessage = try requester.begin(request, store: &store)
  let inspect = try proxy.receive(
    requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
    maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  EngineReport.check(
    inspect == .inspectPrerequisites(operationIdentifier: identifier),
    "a granted request reaches prerequisite inspection")

  try proxy.prerequisitesComplete(operationIdentifier: identifier)
  let approval = try UserApproval(
    for: request, approvedAtMilliseconds: EngineFixture.nowMilliseconds)
  let beginCommand = try proxy.approve(
    operationIdentifier: identifier, approval: approval, store: &store,
    nowMilliseconds: EngineFixture.nowMilliseconds,
    maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  EngineReport.check(
    beginCommand == .beginCardCommand(operationIdentifier: identifier),
    "approval writes the in-flight entry and authorizes the one card command")
  EngineReport.check(
    store.transmissionsRecorded == 1, "exactly one transmission reached storage")
  return true
}

/// Drives one consequential operation from request to acknowledgement.
///
/// Returns the two engines and the store so a caller can inspect what durable
/// state the exchange produced.
internal func driveHappyPath() throws -> HappyPath {
  var store = MemoryJournalStore()
  var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
  var requester = RequesterOperationEngine(recovered: [])
  let request = try engineRequest(operation: signingOperation())
  let identifier = request.operationIdentifier

  guard try driveToCardCommand(&proxy, &requester, &store, request: request) else {
    return HappyPath(proxy: proxy, requester: requester, store: store)
  }

  let reference = try OperationReference(of: request)
  let result = OperationResultMessage.completed(
    reference: reference, result: .signature(EngineFixture.signature))
  let sendResult = try proxy.finishCompleted(
    operationIdentifier: identifier, result: result, store: &store)
  guard case .send(let resultMessage) = sendResult else {
    EngineReport.check(false, "a completed result is retained then released")
    return HappyPath(proxy: proxy, requester: requester, store: store)
  }

  let resultDispatch = try requester.receive(resultMessage, store: &store)
  guard case .sendResultAcknowledgement(_, let ackMessage) = resultDispatch else {
    EngineReport.check(false, "a completed result asks for an acknowledgement")
    return HappyPath(proxy: proxy, requester: requester, store: store)
  }

  let acknowledged = try proxy.receive(
    ackMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
    maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
  EngineReport.check(
    acknowledged == .resultAcknowledged(operationIdentifier: identifier),
    "the proxy records the acknowledgement")

  let released = try requester.acknowledgementReleased(
    operationIdentifier: identifier, store: &store)
  EngineReport.check(
    released == .signature(EngineFixture.signature),
    "the requester releases the signature to its caller")
  EngineReport.check(
    proxy.liveOperationStates[identifier] == .completed
      && requester.liveOperationStates[identifier] == .completed,
    "both engines end the operation completed")
  return HappyPath(proxy: proxy, requester: requester, store: store)
}
