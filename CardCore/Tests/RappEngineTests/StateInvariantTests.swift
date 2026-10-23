// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RappEngine

/// Invariants of the RAPP v26.10.22 formal model, read off the tables the
/// engine carries.
@Suite("RAPP state invariants")
internal struct StateInvariantTests {
  /// The pairing events that may end a pairing: the local user forgetting it,
  /// the close that tells the peer, the notice window, and the peer's notice
  /// (§4.6).
  private static let revokingEvents: Set<PairingEvent> = [
    .forgetPairing, .revocationNoticeSent, .noticeWindowExpired, .peerRevocationNotice,
  ]

  /// Actions that change or end a stored pairing.
  private static let pairingChangingActions: Set<RappAction> = [
    .storePairRecordAtomically, .markRecordConfirmed, .revokeUnconfirmedPairRecord,
    .markRecordRevoked, .sendClosePairingRevoked, .destroyPairKeys, .clearResidualPairRecord,
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

  @Test("No withdrawal changes a stored pairing (INV-14)")
  internal func noWithdrawalChangesAStoredPairing() {
    let pairing = RappModelTables.pairing.filter { $0.event == .peerWithdrawalNotice }
    let session = RappModelTables.session.filter { $0.event == .serviceWithdrawn }
    #expect(!pairing.isEmpty && !session.isEmpty, "the tables name withdrawal")
    for rule in pairing {
      #expect(Self.pairingChangingActions.isDisjoint(with: rule.actions))
      #expect(rule.destination != .revoked && rule.destination != .unpaired)
    }
    for rule in session {
      #expect(Self.pairingChangingActions.isDisjoint(with: rule.actions))
    }
  }

  @Test("Both endpoints withdraw an open session with service_withdrawn (§4.5 items 3 and 8)")
  internal func bothEndpointsWithdraw() throws {
    for role in [EndpointRole.requester, .proxy] {
      let closing = try #require(
        SessionState.transition(from: .healthy, on: .serviceWithdrawn, role: role))
      #expect(closing.state == .closing)
      #expect(closing.actions.first == .sendCloseServiceWithdrawn)
    }
  }

  @Test("A requester's connection not yet open closes without a notice; a custodian's has no rule")
  internal func unopenedConnectionClosesWithoutANotice() throws {
    for state in [SessionState.connecting, .authenticating] {
      let closed = try #require(
        SessionState.transition(from: state, on: .serviceWithdrawn, role: .requester))
      #expect(closed.state == .closed)
      #expect(!closed.actions.contains(.sendCloseServiceWithdrawn))
      #expect(closed.actions == [.destroySessionMaterial, .closeCandidate, .showConnectionStopped])
      #expect(
        SessionState.outcome(from: state, on: .serviceWithdrawn, role: .proxy) == .noRule)
    }
  }

  @Test("Only the custodian shows its computer off, until the pairing's next session (§4.5 item 9)")
  internal func onlyTheCustodianShowsItsPeerOff() throws {
    let off = try #require(
      PairingState.transition(from: .pairedConnected, on: .peerWithdrawalNotice, role: .proxy))
    #expect(off.state == .pairedDisconnected)
    #expect(off.actions == [.showPeerWithdrawn])
    let back = try #require(
      PairingState.transition(from: off.state, on: .sessionHealthy, role: .proxy))
    #expect(back.state == .pairedConnected)
    #expect(
      PairingState.outcome(from: .pairedConnected, on: .peerWithdrawalNotice, role: .requester)
        == .noRule)
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

  @Test("No private-key command before the PIN, and none under the retry floor")
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
