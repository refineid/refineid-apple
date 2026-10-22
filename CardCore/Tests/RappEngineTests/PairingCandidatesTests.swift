// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.22 trying each custodian in pairing mode (section 4.2)")
internal struct PairingCandidatesTests {
  /// The custodians a test makes, each with an offer of its own.
  private static let firstCustodian: UInt8 = 0x01
  private static let secondCustodian: UInt8 = 0x02

  /// One more endpoint than one typed code may open.
  private static let endpointsBeyondTheLimit = (0...PairingCandidateLimit.connections).map {
    index in "endpoint \(index)"
  }

  /// The offer the custodian `custodian` serves on both transports.
  private static func offer(_ custodian: UInt8) throws -> PairingOffer {
    try PairingOffer.create(
      offerIdentifier: filler(custodian, OfferLimit.offerIdentifierSize),
      profiles: ProfileName.allCases.map(\.rawValue),
      transportProfiles: [streamProfile, RappBleGattProfile.name])
  }

  /// Opens the next endpoint, which the test expects to exist.
  private static func open(_ ledger: inout PairingCandidates<String>) throws -> String {
    try #require(try ledger.nextEndpoint())
  }

  @Test("A refusal moves on to the custodian that shows the code")
  internal func aRefusalMovesOn() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("android")
    ledger.found("iphone")
    #expect(try Self.open(&ledger) == "android")
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    #expect(try ledger.closed() == .tryNext)
    #expect(try Self.open(&ledger) == "iphone")
    try ledger.beginTry(try Self.offer(Self.secondCustodian))
    try ledger.accepted()
    #expect(throws: CandidateError.settled) { _ = try ledger.nextEndpoint() }
  }

  @Test("The code is refused only after every custodian refused it")
  internal func refusedOnlyAfterEveryRefusal() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("first")
    ledger.found("second")
    _ = try Self.open(&ledger)
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    #expect(try ledger.closed() == .tryNext)
    _ = try Self.open(&ledger)
    try ledger.beginTry(try Self.offer(Self.secondCustodian))
    #expect(try ledger.closed() == .notAccepted)
    ledger.found("late")
    #expect(throws: CandidateError.settled) { _ = try ledger.nextEndpoint() }
  }

  @Test("An endpoint found during a try is tried too")
  internal func foundDuringATry() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("first")
    _ = try Self.open(&ledger)
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    ledger.found("second")
    #expect(try ledger.closed() == .tryNext)
    #expect(try Self.open(&ledger) == "second")
  }

  @Test("A custodian on two transports receives one guess")
  internal func oneGuessPerOffer() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("stream")
    ledger.found("ble")
    ledger.found("stream")
    _ = try Self.open(&ledger)
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    #expect(try ledger.closed() == .tryNext)
    #expect(try Self.open(&ledger) == "ble")
    #expect(throws: CandidateError.offerAlreadyTried) {
      try ledger.beginTry(try Self.offer(Self.firstCustodian))
    }
    #expect(try ledger.closed() == .notAccepted)
  }

  @Test("One pairing connection at a time")
  internal func oneConnectionAtATime() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("first")
    ledger.found("second")
    _ = try Self.open(&ledger)
    #expect(throws: CandidateError.connectionOpen) { _ = try ledger.nextEndpoint() }
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    #expect(throws: CandidateError.connectionOpen) { _ = try ledger.nextEndpoint() }
    #expect(throws: CandidateError.noConnection) {
      try ledger.beginTry(try Self.offer(Self.secondCustodian))
    }
  }

  @Test("At most the limit of endpoints is opened for one code")
  internal func atMostTheLimitIsOpened() throws {
    var ledger = PairingCandidates<String>()
    for endpoint in Self.endpointsBeyondTheLimit {
      ledger.found(endpoint)
    }
    var opened = 0
    var next = NextCandidate.tryNext
    while next == .tryNext {
      _ = try Self.open(&ledger)
      opened += 1
      try ledger.beginTry(try Self.offer(UInt8(opened)))
      next = try ledger.closed()
    }
    #expect(opened == PairingCandidateLimit.connections)
    #expect(next == .notAccepted)
  }

  @Test("Endpoints that serve no offer are not a refused code")
  internal func noOfferIsNotARefusal() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("session-mode phone")
    _ = try Self.open(&ledger)
    #expect(try ledger.closed() == .noneTried)
    #expect(try ledger.nextEndpoint() == nil)
    ledger.found("pairing phone")
    #expect(try Self.open(&ledger) == "pairing phone")
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    #expect(try ledger.closed() == .notAccepted)
  }

  @Test("Acceptance needs a running try")
  internal func acceptanceNeedsATry() throws {
    var ledger = PairingCandidates<String>()
    #expect(throws: CandidateError.noTry) { try ledger.accepted() }
    #expect(throws: CandidateError.noConnection) { _ = try ledger.closed() }
    ledger.found("only")
    _ = try Self.open(&ledger)
    #expect(throws: CandidateError.noTry) { try ledger.accepted() }
  }

  @Test("A verified T_B ends the search")
  internal func acceptanceEndsTheSearch() throws {
    var ledger = PairingCandidates<String>()
    ledger.found("first")
    ledger.found("second")
    _ = try Self.open(&ledger)
    try ledger.beginTry(try Self.offer(Self.firstCustodian))
    try ledger.accepted()
    #expect(throws: CandidateError.settled) { _ = try ledger.closed() }
    #expect(throws: CandidateError.settled) { _ = try ledger.nextEndpoint() }
  }

  @Test("The outcomes drive the requester's pairing machine")
  internal func outcomesDriveThePairingMachine() throws {
    let tryNext = NextCandidate.tryNext.pairingEvent
    let next = try #require(
      PairingState.transition(
        from: .exchanging, on: tryNext.event, role: .requester, guards: tryNext.guards))
    #expect(next.state == .exchanging)
    #expect(next.actions.contains(.tryNextCandidate))
    #expect(!next.actions.contains(.showWrongCode))

    let notAccepted = NextCandidate.notAccepted.pairingEvent
    #expect(notAccepted.event == .lastCandidateFailed)
    let last = try #require(
      PairingState.transition(
        from: .exchanging, on: notAccepted.event, role: .requester, guards: notAccepted.guards))
    #expect(last.state == .unpaired)
    #expect(last.actions.contains(.showWrongCode))

    let noneTried = NextCandidate.noneTried.pairingEvent
    let none = try #require(
      PairingState.transition(
        from: .exchanging, on: noneTried.event, role: .requester, guards: noneTried.guards))
    #expect(none.actions.contains(.showNoneInPairingMode))
    #expect(!none.actions.contains(.showWrongCode))

    #expect(
      PairingState.outcome(
        from: .exchanging, on: .attemptFailed, role: .requester, guards: notAccepted.guards)
        == .guardFailed(.untriedPairingCandidate),
      "a refusal with nobody left to try never stays exchanging")
  }
}
