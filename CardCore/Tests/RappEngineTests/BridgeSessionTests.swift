// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// How a session ends, and that no failure ends the pairing (RAPP v26.10.29
/// §8.1 item 3, §8.3, §10.1).
@Suite("RAPP session lifetime between the bridges")
internal struct BridgeSessionTests {
  private static let start = OperationFixture.startMilliseconds
  private static let lifetime = OperationFixture.lifetimeMilliseconds
  /// The smallest step of the millisecond clock.
  private static let tick: UInt64 = 1

  /// An inspection the custodian holds, its card turn taken.
  private static func liveRead(
    _ session: LiveSession, _ identifier: RappOperationIdentifier
  ) throws {
    let request = try session.requester.beginInspectCard(
      operationId: identifier, localStartMs: start, expiresAfterMs: lifetime)
    _ = try deliver(request, to: session.custodian, at: start)
  }

  @Test("Closing tells the custodian whether its card command runs on")
  internal func closeEndsTheOperation() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let identifier = OperationFixture.operationIdentifier

    let waiting = try establishedSession(pairing, nowMilliseconds: Self.start)
    try Self.liveRead(waiting, identifier)
    #expect(
      waiting.custodian.closeSession()
        == .sessionClosed(reason: nil, endedOperation: .dropped(identifier)))
    #expect(waiting.custodian.receiveFrame(bytes: Data(), nowMs: Self.start) == .noAction)

    let reading = try establishedSession(pairing, nowMilliseconds: Self.start)
    try Self.liveRead(reading, identifier)
    _ = try reading.custodian.prerequisitesComplete(operationId: identifier, nowMs: Self.start)
    #expect(
      reading.custodian.closeSession()
        == .sessionClosed(reason: nil, endedOperation: .cardExchangeContinues(identifier)))
    #expect(
      (try? reading.custodian.completeInspection(operationId: identifier, answerToReset: Data()))
        == nil, "the card's answer after the close is discarded")
  }

  @Test("A close with a reason reaches the peer and ends its operation")
  internal func closeWithReason() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let identifier = OperationFixture.operationIdentifier
    let session = try establishedSession(pairing, nowMilliseconds: Self.start)
    try Self.liveRead(session, identifier)
    let close = session.requester.closeWithReason(.userDisconnect)
    #expect(
      close
        == .sendClose(
          try frame(close), reason: .userDisconnect, endedOperation: .dropped(identifier)))
    #expect(
      try deliver(close, to: session.custodian, at: Self.start)
        == .sessionClosed(reason: .userDisconnect, endedOperation: .dropped(identifier)))
    #expect(
      session.requester.closeWithReason(.normal)
        == .sessionClosed(reason: nil, endedOperation: nil),
      "a closed session sends nothing more")

    let withdrawn = try establishedSession(pairing, nowMilliseconds: Self.start)
    let notice = withdrawn.custodian.closeWithReason(.serviceWithdrawn)
    #expect(
      try deliver(notice, to: withdrawn.requester, at: Self.start)
        == .sessionClosed(reason: .serviceWithdrawn, endedOperation: nil))
  }

  @Test("A requester's withdrawal reaches the custodian, ends its operation, and keeps the pairing")
  internal func requesterWithdrawal() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let identifier = OperationFixture.operationIdentifier
    let session = try establishedSession(pairing, nowMilliseconds: Self.start)
    try Self.liveRead(session, identifier)
    let notice = session.requester.closeWithReason(.serviceWithdrawn)
    #expect(
      notice
        == .sendClose(
          try frame(notice), reason: .serviceWithdrawn, endedOperation: .dropped(identifier)))
    #expect(
      try deliver(notice, to: session.custodian, at: Self.start)
        == .sessionClosed(reason: .serviceWithdrawn, endedOperation: .dropped(identifier)))
    #expect(
      session.custodian.closeWithReason(.normal)
        == .sessionClosed(reason: nil, endedOperation: nil),
      "the custodian sends no close of its own")

    // The pairing stays: the next session over the same records works.
    let next = try establishedSession(pairing, nowMilliseconds: Self.start)
    let absent = RappCardStatus(card: .absent, reader: .absent)
    #expect(
      try deliver(
        try next.custodian.reportCardStatus(absent), to: next.requester, at: Self.start)
        == .cardStatus(absent))
  }

  @Test("A message the receiving role never receives closes the session, not the pairing")
  internal func violationsCloseTheSession() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let fingerprint = try #require(
      RappCertificateFingerprint(certificate: OperationFixture.certificate))
    let custodianOnly = try establishedSession(pairing, nowMilliseconds: Self.start)
    let violation = custodianOnly.custodian.receiveFrame(
      bytes: try injected(
        .cardStatus, RappCardStatus(card: .present(fingerprint), reader: .absent).wireBody,
        from: custodianOnly.requester),
      nowMs: Self.start)
    #expect(
      violation
        == .sendClose(try frame(violation), reason: .protocolViolation, endedOperation: nil))
    #expect(
      try deliver(violation, to: custodianOnly.requester, at: Self.start)
        == .sessionClosed(reason: .protocolViolation, endedOperation: nil))

    let requesterOnly = try establishedSession(pairing, nowMilliseconds: Self.start)
    let request = try inspectionRequest(OperationFixture.operationIdentifier).wireBody()
    let refused = requesterOnly.requester.receiveFrame(
      bytes: try injected(.operationRequest, request, from: requesterOnly.custodian),
      nowMs: Self.start)
    #expect(
      refused == .sendClose(try frame(refused), reason: .protocolViolation, endedOperation: nil))

    let earlierPhase = try establishedSession(pairing, nowMilliseconds: Self.start)
    let readyAgain = earlierPhase.requester.receiveFrame(
      bytes: try injected(
        .sessionReady,
        try SessionReady(
          parameters: SessionParameters(
            transportProfile: StreamProfile.name,
            candidateIdentifier: TransportRegistry.streamCandidateIdentifier,
            grantsHash: pairing.requester.record.grantsHash),
          nonce: randomBytes(FlowLimit.readyNonce)
        )
        .body(), from: earlierPhase.custodian),
      nowMs: Self.start)
    #expect(
      readyAgain
        == .sendClose(try frame(readyAgain), reason: .protocolViolation, endedOperation: nil))

    // The pairing stays: the next session over the same records works.
    let next = try establishedSession(pairing, nowMilliseconds: Self.start)
    let absent = RappCardStatus(card: .absent, reader: .absent)
    #expect(
      try deliver(
        try next.custodian.reportCardStatus(absent), to: next.requester, at: Self.start)
        == .cardStatus(absent))
  }

  @Test("A card status without the reader's attachment closes the session as a violation")
  internal func cardStatusWithoutReaderIsAViolation() throws {
    let session = try establishedSession(
      try PairedBridges.pair(granting: everyProfile), nowMilliseconds: Self.start)
    var body = RappCardStatus(card: .absent, reader: .attached).wireBody
    body["reader_attached"] = nil
    let refused = session.requester.receiveFrame(
      bytes: try injected(.cardStatus, body, from: session.custodian), nowMs: Self.start)
    #expect(
      refused == .sendClose(try frame(refused), reason: .protocolViolation, endedOperation: nil))
  }

  @Test("A frame that fails authentication ends the session silently")
  internal func integrityFailureEndsTheSession() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let session = try establishedSession(pairing, nowMilliseconds: Self.start)
    var tampered = try frame(
      try session.custodian.reportCardStatus(RappCardStatus(card: .absent, reader: .absent)))
    tampered[tampered.startIndex] ^= tamperByteMask
    #expect(
      session.requester.receiveFrame(bytes: tampered, nowMs: Self.start)
        == .sessionClosed(reason: nil, endedOperation: nil))
  }

  @Test("A ping or pong without its 32-byte challenge closes the session as a violation")
  internal func malformedChallengeIsAViolation() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let bodies: [[String: WireValue]] = [
      [:],
      ["challenge": .bytes(Data("short challenge".utf8))],
      ["challenge": .text("challenge")],
    ]
    for messageType in [MessageType.livenessPing, .livenessPong] {
      for body in bodies {
        let session = try establishedSession(pairing, nowMilliseconds: Self.start)
        let refused = session.custodian.receiveFrame(
          bytes: try injected(messageType, body, from: session.requester), nowMs: Self.start)
        #expect(
          refused
            == .sendClose(try frame(refused), reason: .protocolViolation, endedOperation: nil))
      }
    }
  }

  @Test("The custodian sends session.ready once, then the session is established")
  internal func readyIsSentOnce() throws {
    let (requester, custodian) = try authenticatingSessions(
      try PairedBridges.pair(granting: everyProfile))
    #expect(throws: (any Error).self, "the requester never sends ready") {
      _ = try requester.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
    }
    _ = try custodian.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
    #expect(throws: (any Error).self, "a second ready is refused") {
      _ = try custodian.sendReady(nonce: randomBytes(FlowLimit.readyNonce))
    }
    try custodian.enterEstablished()
    #expect(custodian.isEstablished())
  }

  @Test("Silence brings a ping after five seconds and the end after thirty")
  internal func liveness() throws {
    let session = try establishedSession(
      try PairedBridges.pair(granting: everyProfile), nowMilliseconds: Self.start)
    let ping = LivenessTracker.pingAfterSilenceMilliseconds
    let limit = LivenessTracker.sessionSilenceLimitMilliseconds
    let challenge = OperationFixture.challenge
    #expect(throws: RappBindingError.InvalidInput) {
      _ = try session.requester.pollLiveness(nowMs: Self.start, challenge: Data())
    }
    #expect(
      try session.requester.pollLiveness(nowMs: Self.start + ping - Self.tick, challenge: challenge)
        == .noAction)
    let probe = try session.requester.pollLiveness(nowMs: Self.start + ping, challenge: challenge)
    let echo = try deliver(probe, to: session.custodian, at: Self.start + ping)
    #expect(echo == .sendFrame(try frame(echo), operationId: nil), "a ping is answered at once")
    #expect(try deliver(echo, to: session.requester, at: Self.start + ping) == .noAction)
    let heard = Self.start + ping
    #expect(
      try session.requester.pollLiveness(nowMs: heard + limit - Self.tick, challenge: challenge)
        != .sessionClosed(reason: nil, endedOperation: nil))
    #expect(
      try session.requester.pollLiveness(nowMs: heard + limit, challenge: challenge)
        == .sessionClosed(reason: nil, endedOperation: nil))
  }
}
