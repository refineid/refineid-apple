// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.29 a busy custodian is tried again quietly (section 4.2)")
internal struct PairingCandidatesBusyTests {
  /// The monotonic time of the searches that do not wait.
  internal static let now: UInt64 = 10_000
  /// A custodian's busy wait.
  private static let retryAfter: UInt64 = 400
  /// The custodians a test makes, each with an offer of its own.
  private static let firstCustodian: UInt8 = 0x01
  private static let secondCustodian: UInt8 = 0x02

  /// Opens the next endpoint at `time`, which the test expects to be due.
  internal static func open(
    _ ledger: inout PairingCandidates<String>, at time: UInt64
  ) throws -> String {
    guard case .open(let endpoint) = try ledger.nextEndpoint(nowMilliseconds: time) else {
      Issue.record("an endpoint is due at \(time)")
      throw CandidateError.noConnection
    }
    return endpoint
  }

  /// The offer the custodian `custodian` serves on both transports.
  private static func offer(_ custodian: UInt8) throws -> PairingOffer {
    try PairingOffer.create(
      offerIdentifier: filler(custodian, OfferLimit.offerIdentifierSize),
      profiles: ProfileName.allCases.map(\.rawValue),
      transportProfiles: [streamProfile, RappBleGattProfile.name])
  }

  @Test("A busy custodian is opened again after the others and after its wait")
  internal func aBusyCustodianIsDeferred() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("busy")
    ledger.found("other")
    #expect(try Self.open(&ledger, at: Self.now) == "busy")
    #expect(
      try ledger.busy(retryAfterMilliseconds: Self.retryAfter, nowMilliseconds: Self.now)
        == .deferred)
    #expect(
      try Self.open(&ledger, at: Self.now) == "other", "the endpoint still waiting goes first")
    try ledger.beginTry(try Self.offer(Self.secondCustodian))
    #expect(try ledger.closed() == .tryNext)
    #expect(
      try ledger.nextEndpoint(nowMilliseconds: Self.now + 1)
        == .notBefore(Self.now + Self.retryAfter))
    #expect(try Self.open(&ledger, at: Self.now + Self.retryAfter) == "busy")
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    try ledger.accepted()
  }

  @Test("A busy answer in place of step 2 is not a try of the offer")
  internal func aBusyAnswerGivesTheOfferBack() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("phone")
    _ = try Self.open(&ledger, at: Self.now)
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    #expect(try ledger.busy(retryAfterMilliseconds: 0, nowMilliseconds: Self.now) == .deferred)
    #expect(try Self.open(&ledger, at: Self.now) == "phone", "no wait opens it again at once")
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    #expect(try ledger.closed() == .notAccepted)
  }

  @Test("Every reopening counts, and a custodian still busy at the limit refused the code")
  internal func stillBusyAtTheLimitIsNotAccepted() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("phone")
    var time = Self.now
    var next = NextCandidate.deferred
    var openings = 0
    while next == .deferred {
      _ = try Self.open(&ledger, at: time)
      openings += 1
      next = try ledger.busy(retryAfterMilliseconds: Self.retryAfter, nowMilliseconds: time)
      time += Self.retryAfter
    }
    #expect(openings == PairingCandidateLimit.connections)
    #expect(next == .notAccepted, "busy and nothing tried is not none in pairing mode")
    #expect(throws: CandidateError.settled) { _ = try ledger.nextEndpoint(nowMilliseconds: time) }
  }

  @Test("A busy outcome drives the requester's pairing machine without a report")
  internal func busyDrivesThePairingMachine() throws {
    let deferred = NextCandidate.deferred.pairingEvent(remoteUseAvailable: true)
    #expect(deferred.event == .candidateBusy)
    let next = try #require(
      PairingState.transition(
        from: .exchanging, on: deferred.event, role: .requester, guards: deferred.guards))
    #expect(next.state == .exchanging)
    #expect(next.actions.contains(.deferCandidate))
    #expect(!next.actions.contains(.showWrongCode))
    #expect(!next.actions.contains(.showNoneInPairingMode))
    #expect(
      NextCandidate.deferred.pairingEvent(remoteUseAvailable: false).event == .searchInterrupted)
    for state in [PairingState.offering, .exchanging] {
      let refused = try #require(
        PairingState.transition(from: state, on: .attemptRefused, role: .proxy))
      #expect(refused.state == state, "the offer stays as it was")
      #expect(refused.actions == [.answerBusy])
    }
  }
}
