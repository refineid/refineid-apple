// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// What the custodian refuses before admitting an operation, and what the
/// requester makes of it (RAPP v26.10.22 §8.1, §8.2 item 1, §10.3).
@Suite("RAPP refusals between the bridges")
internal struct BridgeRefusalTests {
  private static let start = OperationFixture.startMilliseconds
  private static let lifetime = OperationFixture.lifetimeMilliseconds
  /// The lifetime §8.1 item 2 refuses.
  private static let zeroLifetime: UInt64 = 0

  /// The registered `error` name and `status` a custodian frame carries.
  private static func refusal(
    _ action: RappBridgeAction, readBy session: LiveSession
  ) throws -> (name: String?, status: String?) {
    let envelope = try opened(try frame(action), by: session.requester)
    var name: String?
    var status: String?
    if case .text(let value)? = envelope.body["error_name"] ?? envelope.body["error"] {
      name = value
    }
    if case .text(let value)? = envelope.body["status"] {
      status = value
    }
    return (name, status)
  }

  @Test("A second request while one is live is busy; a reused identifier is a duplicate")
  internal func busyAndDuplicate() throws {
    let session = try establishedSession(
      try PairedBridges.pair(granting: everyProfile), nowMilliseconds: Self.start)
    let first = OperationFixture.operationIdentifier
    let second = OperationFixture.otherOperation
    let live = try injected(
      .operationRequest, try inspectionRequest(first).wireBody(), from: session.requester)
    #expect(
      session.custodian.receiveFrame(bytes: live, nowMs: Self.start)
        == .custodianStep(first, .inspectPrerequisites, RappOperationDescriptor(.inspectCard)))
    let busy = session.custodian.receiveFrame(
      bytes: try injected(
        .operationRequest, try inspectionRequest(second).wireBody(), from: session.requester),
      nowMs: Self.start)
    #expect(try Self.refusal(busy, readBy: session).name == ResultError.busy.rawValue)
    _ = try session.custodian.prerequisitesComplete(operationId: first, nowMs: Self.start)
    let answer = try session.custodian.completeInspection(
      operationId: first, answerToReset: Data())
    #expect(try Self.refusal(answer, readBy: session).status == ResultStatus.completed.rawValue)
    for identifier in [first, second] {
      let duplicate = session.custodian.receiveFrame(
        bytes: try injected(
          .operationRequest, try inspectionRequest(identifier).wireBody(),
          from: session.requester),
        nowMs: Self.start)
      #expect(
        try Self.refusal(duplicate, readBy: session).name
          == ResultError.duplicateOperation.rawValue,
        "an identifier the session has seen, admitted or refused, is used once")
    }
  }

  @Test("The requester learns busy and duplicate_operation as the operation's end")
  internal func requesterLearnsTheRefusal() throws {
    let session = try establishedSession(
      try PairedBridges.pair(granting: everyProfile), nowMilliseconds: Self.start)
    let foreign = OperationFixture.otherOperation
    _ = session.custodian.receiveFrame(
      bytes: try injected(
        .operationRequest, try inspectionRequest(foreign).wireBody(), from: session.requester),
      nowMs: Self.start)
    let identifier = OperationFixture.operationIdentifier
    let request = try session.requester.beginInspectCard(
      operationId: identifier, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
    let busy = try deliver(request, to: session.custodian, at: Self.start)
    #expect(
      try deliver(busy, to: session.requester, at: Self.start) == .terminal(identifier, .busy))

    let again = OperationFixture.identifier(OperationFill.challenge)
    // Every custodian frame the requester's bridge does not act on is still
    // opened in order, so the two cipher states stay in step.
    _ = try session.custodian.prerequisitesComplete(operationId: foreign, nowMs: Self.start)
    _ = try opened(
      try frame(try session.custodian.cardError(operationId: foreign)), by: session.requester)
    _ = session.custodian.receiveFrame(
      bytes: try injected(
        .operationRequest, try inspectionRequest(again).wireBody(), from: session.requester),
      nowMs: Self.start)
    _ = try session.custodian.prerequisitesComplete(operationId: again, nowMs: Self.start)
    _ = try opened(
      try frame(try session.custodian.cardError(operationId: again)), by: session.requester)
    let retried = try session.requester.beginInspectCard(
      operationId: again, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
    let duplicate = try deliver(retried, to: session.custodian, at: Self.start)
    #expect(
      try deliver(duplicate, to: session.requester, at: Self.start)
        == .terminal(again, .duplicateOperation))
  }

  @Test("A well-formed request naming an unregistered action is unsupported")
  internal func unsupportedAction() throws {
    let session = try establishedSession(
      try PairedBridges.pair(granting: everyProfile), nowMilliseconds: Self.start)
    var body = try inspectionRequest(OperationFixture.operationIdentifier).wireBody()
    body["action"] = .text("format_card")
    let refused = session.custodian.receiveFrame(
      bytes: try injected(.operationRequest, body, from: session.requester), nowMs: Self.start)
    let unsupported = try Self.refusal(refused, readBy: session)
    #expect(unsupported.name == ResultError.unsupportedParameter.rawValue)
    #expect(unsupported.status == ResultStatus.rejected.rawValue)
  }

  @Test("An ungranted profile is unauthorized and a zero lifetime invalid")
  internal func unauthorizedAndInvalidLifetime() throws {
    let session = try establishedSession(
      try PairedBridges.pair(granting: [.cardStatus]), nowMilliseconds: Self.start)
    let ungranted = session.custodian.receiveFrame(
      bytes: try injected(
        .operationRequest,
        try browserRequest(
          OperationFixture.operationIdentifier, expiresAfterMilliseconds: Self.lifetime
        )
        .wireBody(), from: session.requester),
      nowMs: Self.start)
    let unauthorized = try Self.refusal(ungranted, readBy: session)
    #expect(unauthorized.name == ResultError.unauthorized.rawValue)
    #expect(unauthorized.status == ResultStatus.rejected.rawValue)

    var body = try inspectionRequest(OperationFixture.otherOperation).wireBody()
    body["expires_after_ms"] = .unsigned(Self.zeroLifetime)
    let zero = session.custodian.receiveFrame(
      bytes: try injected(.operationRequest, body, from: session.requester), nowMs: Self.start)
    let invalid = try Self.refusal(zero, readBy: session)
    #expect(invalid.name == ResultError.invalidLifetime.rawValue)
    #expect(invalid.status == ResultStatus.rejected.rawValue)
  }
}
