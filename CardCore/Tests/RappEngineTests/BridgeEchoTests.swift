// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// Acknowledged goodbyes and the requester's hello between the bridges
/// (RAPP v26.11.8 §7.1 items 6 and 7).
@Suite("RAPP close echoes and the requester's hello")
internal struct BridgeEchoTests {
  private static let start = OperationFixture.startMilliseconds

  @Test("While a close waits for its echo, other messages are ignored and the echo is not answered")
  internal func echoWait() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let session = try establishedSession(pairing, nowMilliseconds: Self.start)
    let close = session.requester.closeWithReason(.serviceWithdrawn)
    let status = try session.custodian.reportCardStatus(
      RappCardStatus(card: .absent, reader: .absent))
    #expect(try deliver(status, to: session.requester, at: Self.start) == .noAction)
    #expect(
      try session.requester.pollLiveness(
        nowMs: Self.start + LivenessTracker.sessionSilenceLimitMilliseconds,
        challenge: OperationFixture.challenge) == .noAction,
      "liveness stops once the close is sent")
    let echo = try deliver(close, to: session.custodian, at: Self.start)
    #expect(
      try deliver(echo, to: session.requester, at: Self.start)
        == .closeAcknowledged(reason: .serviceWithdrawn, crossing: false))
    #expect(
      session.requester.closeSession() == .sessionClosed(reason: nil, endedOperation: nil))
  }

  @Test("Two closes that cross acknowledge each other and neither is answered")
  internal func crossingCloses() throws {
    let pairing = try PairedBridges.pair(granting: everyProfile)
    let session = try establishedSession(pairing, nowMilliseconds: Self.start)
    let fromRequester = session.requester.closeWithReason(.serviceWithdrawn)
    let fromCustodian = session.custodian.closeWithReason(.pairingRevoked)
    #expect(
      try deliver(fromCustodian, to: session.requester, at: Self.start)
        == .closeAcknowledged(reason: .pairingRevoked, crossing: true))
    #expect(
      try deliver(fromRequester, to: session.custodian, at: Self.start)
        == .closeAcknowledged(reason: .serviceWithdrawn, crossing: true))
  }

  @Test("A custodian admits nothing before the requester's hello but a close")
  internal func helloComesFirst() throws {
    let granted: [ProfileName] = [.cardStatus]
    for first in [MessageType.operationRequest, .livenessPing] {
      let (requesterChannel, custodianChannel) = matchedMessageChannels()
      var requester = requesterChannel
      let custodian = try RappOperationBridge(
        session: EstablishedSession(
          role: .proxy, pairIdentifier: Data(count: PairRecordSize.pairIdentifier),
          sessionIdentifier: matchedSessionIdentifier, channel: custodianChannel),
        grantedProfiles: granted, side: .proxy(ProxyOperationEngine(grantedProfiles: granted)),
        maximumLifetimeMs: OperationFixture.maximumLifetimeMilliseconds,
        nowMilliseconds: Self.start)
      let body: [String: WireValue] =
        first == .operationRequest
        ? try inspectionRequest(OperationFixture.operationIdentifier).wireBody()
        : ["challenge": .bytes(OperationFixture.challenge)]
      let refused = custodian.receiveFrame(
        bytes: try requester.seal(first, body: body), nowMs: Self.start)
      #expect(
        refused
          == .sendClose(try frame(refused), reason: .protocolViolation, endedOperation: nil),
        "\(first.rawValue) before the hello is a protocol violation")
    }
  }
}
