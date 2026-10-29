// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.29 a requester's tries of one code over real pairing bridges")
internal struct RappPairingCandidatesTests {
  /// The code the right phone shows and the user types.
  private static let typedCode = "7KX4M9"
  /// The code the other phone in pairing mode shows.
  private static let otherCode = "3HQ8TW"
  private static let candidate = TransportRegistry.streamCandidateIdentifier
  private static let now: UInt64 = 1_000
  private static let spacing = RappPreAuthenticationLimiter.minimumSpacingMilliseconds

  /// A phone in pairing mode showing `code`, serving its offer on `transports`.
  private static func custodian(
    showing code: String, transports: [String]
  ) throws -> RappPairingBridge {
    try RappPairingBridge.custodianOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: ProfileName.allCases.map(\.rawValue), transportProfiles: transports,
      startedAtMonotonicMs: now)
  }

  /// The requester's side of a connection to `custodian` over `transport`,
  /// opened at `time`.
  private static func requester(
    of custodian: RappPairingBridge, transport: String, at time: UInt64 = now
  ) throws -> RappPairingBridge {
    try RappPairingBridge.bootstrapOffer(
      bootstrap: try custodian.bootstrapBytes(nowMonotonicMs: time), transportProfile: transport,
      pairingCode: typedCode, startedAtMonotonicMs: time)
  }

  /// Runs CPace through the requester's check of T_B.
  private static func tryCode(
    requester: RappPairingBridge, custodian: RappPairingBridge
  ) throws {
    let random = randomBytes(RappCpaceConstants.wideScalarSize)
    try requester.beginCpace(candidateId: candidate, randomBytes64: random, nowMonotonicMs: now)
    try custodian.beginCpace(candidateId: candidate, randomBytes64: random, nowMonotonicMs: now)
    try custodian.readCpaceFrame(
      bytes: try requester.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try requester.readCpaceFrame(
      bytes: try custodian.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
  }

  @Test("A requester tries the next phone before refusing the code")
  internal func triesTheNextPhone() throws {
    let other = try Self.custodian(showing: Self.otherCode, transports: [streamProfile])
    let right = try Self.custodian(showing: Self.typedCode, transports: [streamProfile])
    let candidates = RappPairingCandidates<String>()
    candidates.found("other")
    candidates.found("right")

    #expect(try candidates.nextEndpoint(nowMonotonicMs: Self.now) == .open("other"))
    let first = try Self.requester(of: other, transport: streamProfile)
    #expect(try candidates.beginTry(first))
    #expect(throws: RappBindingError.ProtocolFailure) {
      try Self.tryCode(requester: first, custodian: other)
    }
    #expect(try candidates.closed(remoteUseAvailable: true) == .tryNext)

    #expect(try candidates.nextEndpoint(nowMonotonicMs: Self.now) == .open("right"))
    let second = try Self.requester(of: right, transport: streamProfile)
    #expect(try candidates.beginTry(second))
    try Self.tryCode(requester: second, custodian: right)
    try candidates.accepted()
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try candidates.nextEndpoint(nowMonotonicMs: Self.now)
    }
  }

  @Test("A phone found on two transports receives one guess")
  internal func aPhoneFoundTwiceGetsOneGuess() throws {
    let phone = try Self.custodian(
      showing: Self.otherCode, transports: [streamProfile, RappBleGattProfile.name])
    let candidates = RappPairingCandidates<String>()
    candidates.found("stream")
    candidates.found("ble")

    _ = try candidates.nextEndpoint(nowMonotonicMs: Self.now)
    let first = try Self.requester(of: phone, transport: streamProfile)
    #expect(try candidates.beginTry(first))
    #expect(throws: RappBindingError.ProtocolFailure) {
      try Self.tryCode(requester: first, custodian: phone)
    }
    #expect(phone.candidateFailed(nowMonotonicMs: Self.now), "the phone keeps its offer")
    #expect(try candidates.closed(remoteUseAvailable: true) == .tryNext)

    _ = try candidates.nextEndpoint(nowMonotonicMs: Self.now)
    let again = try Self.requester(
      of: phone, transport: RappBleGattProfile.name, at: Self.now + Self.spacing)
    #expect(try candidates.beginTry(again) == false)
    #expect(try candidates.closed(remoteUseAvailable: true) == .notAccepted)
  }

  @Test("A local card or remote use off ends the search; a refused code is still reported")
  internal func unavailableRemoteUseInterrupts() throws {
    let other = try Self.custodian(showing: Self.otherCode, transports: [streamProfile])
    let candidates = RappPairingCandidates<String>()
    candidates.found("other")
    candidates.found("right")
    _ = try candidates.nextEndpoint(nowMonotonicMs: Self.now)
    let first = try Self.requester(of: other, transport: streamProfile)
    #expect(try candidates.beginTry(first))
    #expect(throws: RappBindingError.ProtocolFailure) {
      try Self.tryCode(requester: first, custodian: other)
    }
    #expect(try candidates.closed(remoteUseAvailable: false) == .interrupted)

    let another = try Self.custodian(showing: Self.otherCode, transports: [streamProfile])
    let refused = RappPairingCandidates<String>()
    refused.found("only")
    _ = try refused.nextEndpoint(nowMonotonicMs: Self.now)
    let only = try Self.requester(of: another, transport: streamProfile)
    #expect(try refused.beginTry(only))
    #expect(throws: RappBindingError.ProtocolFailure) {
      try Self.tryCode(requester: only, custodian: another)
    }
    #expect(try refused.closed(remoteUseAvailable: false) == .notAccepted)

    let unseen = RappPairingCandidates<String>()
    unseen.found("silent")
    _ = try unseen.nextEndpoint(nowMonotonicMs: Self.now)
    #expect(try unseen.closed(remoteUseAvailable: false) == .interrupted)
  }

  @Test("Only a requester's offer awaiting CPace begins a try")
  internal func onlyAnUntriedRequesterOffer() throws {
    let custodian = try Self.custodian(showing: Self.typedCode, transports: [streamProfile])
    let candidates = RappPairingCandidates<String>()
    candidates.found("phone")
    _ = try candidates.nextEndpoint(nowMonotonicMs: Self.now)
    #expect(throws: RappBindingError.WrongPhase) { _ = try candidates.beginTry(custodian) }
    let requester = try Self.requester(of: custodian, transport: streamProfile)
    try requester.beginCpace(
      candidateId: Self.candidate, randomBytes64: randomBytes(RappCpaceConstants.wideScalarSize),
      nowMonotonicMs: Self.now)
    #expect(throws: RappBindingError.WrongPhase) { _ = try candidates.beginTry(requester) }
  }

  @Test("A busy phone is asked again after its wait, after the other phone")
  internal func aBusyPhoneIsAskedAgain() throws {
    let busyPhone = try Self.custodian(showing: Self.typedCode, transports: [streamProfile])
    let other = try Self.custodian(showing: Self.otherCode, transports: [streamProfile])
    let candidates = RappPairingCandidates<String>()
    candidates.found("busy")
    candidates.found("other")

    // Another computer's attempt holds the busy phone.
    let elsewhere = try Self.requester(of: busyPhone, transport: streamProfile)
    try Self.tryCode(requester: elsewhere, custodian: busyPhone)
    #expect(try candidates.nextEndpoint(nowMonotonicMs: Self.now) == .open("busy"))
    let answer = try busyPhone.bootstrapBytes(nowMonotonicMs: Self.now)
    #expect(throws: RappBindingError.CustodianBusy) {
      _ = try RappPairingBridge.bootstrapOffer(
        bootstrap: answer, transportProfile: streamProfile, pairingCode: Self.typedCode,
        startedAtMonotonicMs: Self.now)
    }
    let wait = try rappPairingBusyRetryAfterMs(answer)
    #expect(
      try candidates.busy(retryAfterMs: wait, nowMonotonicMs: Self.now, remoteUseAvailable: true)
        == .deferred)

    #expect(try candidates.nextEndpoint(nowMonotonicMs: Self.now) == .open("other"))
    let first = try Self.requester(of: other, transport: streamProfile)
    #expect(try candidates.beginTry(first))
    #expect(throws: RappBindingError.ProtocolFailure) {
      try Self.tryCode(requester: first, custodian: other)
    }
    #expect(try candidates.closed(remoteUseAvailable: true) == .tryNext)
    #expect(
      try candidates.nextEndpoint(nowMonotonicMs: Self.now)
        == .notBefore(monotonicMs: Self.now + wait))

    // The other computer hangs up; the phone frees its attempt slot.
    let reopened = Self.now + wait
    #expect(busyPhone.candidateFailed(nowMonotonicMs: reopened))
    #expect(try candidates.nextEndpoint(nowMonotonicMs: reopened) == .open("busy"))
    let second = try Self.requester(of: busyPhone, transport: streamProfile, at: reopened)
    #expect(try candidates.beginTry(second))
    let random = randomBytes(RappCpaceConstants.wideScalarSize)
    try second.beginCpace(
      candidateId: Self.candidate, randomBytes64: random, nowMonotonicMs: reopened)
    try busyPhone.beginCpace(
      candidateId: Self.candidate, randomBytes64: random, nowMonotonicMs: reopened)
    try busyPhone.readCpaceFrame(
      bytes: try second.writeCpaceFrame(nowMonotonicMs: reopened), nowMonotonicMs: reopened)
    try second.readCpaceFrame(
      bytes: try busyPhone.writeCpaceFrame(nowMonotonicMs: reopened), nowMonotonicMs: reopened)
    try candidates.accepted()
  }

  @Test("A phone still busy at the connection limit counts as refusing the code")
  internal func stillBusyAtTheLimit() throws {
    let candidates = RappPairingCandidates<String>()
    candidates.found("phone")
    var time = Self.now
    var next = RappNextCandidate.deferred
    var openings = 0
    while next == .deferred {
      #expect(try candidates.nextEndpoint(nowMonotonicMs: time) == .open("phone"))
      openings += 1
      next = try candidates.busy(
        retryAfterMs: Self.spacing, nowMonotonicMs: time, remoteUseAvailable: true)
      time += Self.spacing
    }
    #expect(openings == PairingCandidateLimit.connections)
    #expect(next == .notAccepted, "a busy answer and nothing tried is not none in pairing mode")
  }

  @Test("A wait beyond the schema is refused, and no wait reopens at once")
  internal func busyWaitsAreChecked() throws {
    let candidates = RappPairingCandidates<String>()
    candidates.found("phone")
    _ = try candidates.nextEndpoint(nowMonotonicMs: Self.now)
    #expect(throws: RappBindingError.InvalidInput) {
      _ = try candidates.busy(
        retryAfterMs: PairingBusy.maximumRetryAfterMilliseconds + 1, nowMonotonicMs: Self.now,
        remoteUseAvailable: true)
    }
    #expect(
      try candidates.busy(retryAfterMs: 0, nowMonotonicMs: Self.now, remoteUseAvailable: true)
        == .deferred)
    #expect(try candidates.nextEndpoint(nowMonotonicMs: Self.now) == .open("phone"))
    #expect(
      try candidates.busy(retryAfterMs: 0, nowMonotonicMs: Self.now, remoteUseAvailable: false)
        == .interrupted)
  }
}
