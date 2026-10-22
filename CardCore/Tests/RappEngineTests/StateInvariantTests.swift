// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RappEngine

/// Invariants of the RAPP v26.10.21 formal model, read off the tables the
/// engine carries.
@Suite("RAPP state invariants")
internal struct StateInvariantTests {
  /// The pairing events that may end a pairing: the local user forgetting it,
  /// the close that tells the peer, the notice window, and the peer's notice
  /// (§4.6).
  private static let revokingEvents: Set<PairingEvent> = [
    .forgetPairing, .revocationNoticeSent, .noticeWindowExpired, .peerRevocationNotice,
  ]

  @Test("No failure revokes a pairing (INV-08)")
  internal func noFailureRevokesAPairing() {
    for rule in RappModelTables.pairing
    where rule.destination == .revoked || rule.destination == .revoking {
      #expect(Self.revokingEvents.contains(rule.event), "\(rule.event.rawValue)")
    }
    let failures: [SessionEvent] = [
      .authenticatedProtocolViolation, .sessionIntegrityFailed, .transportFailed,
      .silenceLimitReached, .candidateFailure,
    ]
    for rule in RappModelTables.session where failures.contains(rule.event) {
      #expect(
        !rule.actions.contains(.markRecordRevoked) && !rule.actions.contains(.destroyPairKeys),
        "\(rule.event.rawValue) leaves the pairing")
    }
  }

  @Test("Nothing of an operation outlives its session (INV-13)")
  internal func sessionCloseEndsTheOperation() {
    let closing = RappModelTables.operation.filter { $0.event == .sessionClosed }
    #expect(!closing.isEmpty)
    for rule in closing {
      #expect(rule.destination == .idle, "\(rule.from.map(\.rawValue))")
    }
  }

  @Test("Only the custodian sends session.ready, then card.status")
  internal func readyIsTheCustodians() throws {
    let custodian = try #require(
      SessionState.transition(from: .authenticating, on: .handshakeComplete, role: .proxy))
    #expect(custodian.state == .healthy)
    let ready = try #require(custodian.actions.firstIndex(of: .sendSessionReady))
    let status = try #require(custodian.actions.firstIndex(of: .sendCardStatus))
    #expect(ready < status)
    let requester = try #require(
      SessionState.transition(from: .authenticating, on: .handshakeComplete, role: .requester))
    #expect(requester.state == .authenticating)
    #expect(!requester.actions.contains(.sendSessionReady))
  }

  @Test("No private-key command before consent, and none under the retry floor")
  internal func consentAndRetryFloorPrecedeTheCard() throws {
    for rule in RappModelTables.operation where rule.actions.contains(.consumeCardCommand) {
      #expect(rule.from == [.awaitingConsent] && rule.event == .userApproved)
      let floor = try #require(rule.actions.firstIndex(of: .checkRetryFloor))
      let command = try #require(rule.actions.firstIndex(of: .consumeCardCommand))
      #expect(floor < command)
    }
    let read = try #require(
      OperationState.transition(from: .requested, on: .cardAcquiredForRead, role: .proxy))
    #expect(!read.actions.contains(.presentConsent))
  }
}
