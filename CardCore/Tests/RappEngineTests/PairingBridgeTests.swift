// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.29 pairing bridge: CPace KC2, attempt admission, ceremony")
internal struct PairingBridgeTests {
  private static let code = "7KX4M9"
  private static let wrongCode = "7KX4M8"
  private static let candidate = TransportRegistry.streamCandidateIdentifier
  private static let profiles = [
    "fi.refineid.card-status", "fi.refineid.authentication",
    "fi.refineid.document-signing",
  ]
  private static let attemptWindow = CpaceAttemptSlot.attemptWindowMilliseconds
  /// More failed attempts than any per-offer count would admit.
  private static let repeatedAttempts = 8
  /// The custodian's spacing between CPace starts (§3.3 item 6).
  private static let spacing = RappPreAuthenticationLimiter.minimumSpacingMilliseconds

  /// The custodian's offer over the stream transport.
  private static func custodian(code: String) throws -> RappPairingBridge {
    try RappPairingBridge.custodianOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: profiles, transportProfiles: [streamProfile], startedAtMonotonicMs: 0)
  }

  /// The requester's side, from the offer the custodian serves at `time`.
  private static func requester(
    of custodian: RappPairingBridge, code: String, at time: UInt64 = 0
  ) throws -> RappPairingBridge {
    try RappPairingBridge.bootstrapOffer(
      bootstrap: try custodian.bootstrapBytes(nowMonotonicMs: time),
      transportProfile: streamProfile, pairingCode: code, startedAtMonotonicMs: time)
  }

  /// The time of the `attempt`th attempt from `start`, one spacing apart.
  private static func attemptTime(_ attempt: Int, from start: UInt64) -> UInt64 {
    start + UInt64(attempt) * spacing
  }

  private static func random() -> Data { randomBytes(RappCpaceConstants.wideScalarSize) }

  /// Runs CPace steps 1 and 2; returns the requester's step 3.
  private static func cpaceToStepThree(
    requester: RappPairingBridge, custodian: RappPairingBridge, now: UInt64
  ) throws -> Data {
    try requester.beginCpace(candidateId: candidate, randomBytes64: random(), nowMonotonicMs: now)
    try custodian.beginCpace(candidateId: candidate, randomBytes64: random(), nowMonotonicMs: now)
    try custodian.readCpaceFrame(
      bytes: try requester.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try requester.readCpaceFrame(
      bytes: try custodian.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    return try requester.writeCpaceFrame(nowMonotonicMs: now)
  }

  /// The right code still consumes the offer.
  private static func expectOfferConsumed(by custodian: RappPairingBridge, now: UInt64) throws {
    let requester = try requester(of: custodian, code: code, at: now)
    let stepThree = try cpaceToStepThree(requester: requester, custodian: custodian, now: now)
    try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now)
    #expect(custodian.candidateFailed(nowMonotonicMs: now) == false)
  }

  @Test("Requester and custodian agree on one pairing from the served offer and the code")
  internal func ceremonyCompletes() throws {
    let custodian = try Self.custodian(code: Self.code)
    let requester = try Self.requester(of: custodian, code: Self.code)
    let now: UInt64 = 1_000
    let stepThree = try Self.cpaceToStepThree(
      requester: requester, custodian: custodian, now: now)
    try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now)

    try custodian.readHandshakeFrame(
      bytes: try requester.writeHandshakeFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try requester.readHandshakeFrame(
      bytes: try custodian.writeHandshakeFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try custodian.readHandshakeFrame(
      bytes: try requester.writeHandshakeFrame(nowMonotonicMs: now), nowMonotonicMs: now)
    try requester.enterConfirmation(nowMonotonicMs: now)
    try custodian.enterConfirmation(nowMonotonicMs: now)

    let requesterHello = try requester.sendHello(
      displayName: "Mac", platform: "macOS", nowMonotonicMs: now)
    let introduced = try custodian.receiveHello(bytes: requesterHello, nowMonotonicMs: now)
    #expect(introduced.requestedProfiles == Self.profiles.sorted())
    _ = try requester.receiveHello(
      bytes: try custodian.sendHello(displayName: "iPhone", platform: "iOS", nowMonotonicMs: now),
      nowMonotonicMs: now)
    let granted = try requester.receiveConfirmation(
      bytes: try custodian.sendConfirmation(grantedProfiles: Self.profiles, nowMonotonicMs: now),
      nowMonotonicMs: now)
    _ = try custodian.receiveConfirmation(
      bytes: try requester.sendConfirmation(grantedProfiles: granted, nowMonotonicMs: now),
      nowMonotonicMs: now)

    _ = try requester.buildPairRecord(createdAtMs: 0, nowMonotonicMs: now)
    _ = try custodian.buildPairRecord(createdAtMs: 0, nowMonotonicMs: now)
    let requesterStored = try requester.sendStored(nowMonotonicMs: now)
    let custodianStored = try custodian.sendStored(nowMonotonicMs: now)
    try custodian.receiveStored(bytes: requesterStored, nowMonotonicMs: now)
    try requester.receiveStored(bytes: custodianStored, nowMonotonicMs: now)
    guard let requesterRecord = try requester.activatePairing(nowMonotonicMs: now),
      let custodianRecord = try custodian.activatePairing(nowMonotonicMs: now)
    else {
      Issue.record("both storage confirmations make the pairing active")
      return
    }
    #expect(requesterRecord.metadata().storageConfirmed)
    #expect(custodianRecord.metadata().storageConfirmed)
    #expect(requesterRecord.metadata().pairId == custodianRecord.metadata().pairId)
    #expect(requesterRecord.metadata().profiles == custodianRecord.metadata().profiles)
    #expect(custodian.candidateFailed(nowMonotonicMs: now) == false)
  }

  @Test("Wrong codes never end the custodian's offer")
  internal func wrongCodesKeepTheOffer() throws {
    let custodian = try Self.custodian(code: Self.code)
    let start: UInt64 = 1_000
    for attempt in 0..<Self.repeatedAttempts {
      let now = Self.attemptTime(attempt, from: start)
      let requester = try Self.requester(of: custodian, code: Self.wrongCode, at: now)
      try requester.beginCpace(
        candidateId: Self.candidate, randomBytes64: Self.random(), nowMonotonicMs: now)
      try custodian.beginCpace(
        candidateId: Self.candidate, randomBytes64: Self.random(), nowMonotonicMs: now)
      try custodian.readCpaceFrame(
        bytes: try requester.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
      #expect(throws: RappBindingError.ProtocolFailure) {
        try requester.readCpaceFrame(
          bytes: try custodian.writeCpaceFrame(nowMonotonicMs: now), nowMonotonicMs: now)
      }
      // The requester saw the tag fail and dropped the link without sending T_A.
      #expect(custodian.candidateFailed(nowMonotonicMs: now))
    }
    try Self.expectOfferConsumed(
      by: custodian, now: Self.attemptTime(Self.repeatedAttempts, from: start))
  }

  @Test("A forged T_A frees the slot and keeps the offer")
  internal func forgedTagKeepsTheOffer() throws {
    let custodian = try Self.custodian(code: Self.code)
    let start: UInt64 = 1_000
    for attempt in 0..<Self.repeatedAttempts {
      let now = Self.attemptTime(attempt, from: start)
      let requester = try Self.requester(of: custodian, code: Self.code, at: now)
      var stepThree = try Self.cpaceToStepThree(
        requester: requester, custodian: custodian, now: now)
      stepThree[stepThree.startIndex] ^= 1
      #expect(throws: RappBindingError.ProtocolFailure) {
        try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now)
      }
    }
    try Self.expectOfferConsumed(
      by: custodian, now: Self.attemptTime(Self.repeatedAttempts, from: start))
  }

  @Test("One attempt at a time: a second start waits for the first to end")
  internal func singleFlight() throws {
    let custodian = try Self.custodian(code: Self.code)
    let now: UInt64 = 1_000
    let requester = try Self.requester(of: custodian, code: Self.code, at: now)
    _ = try Self.cpaceToStepThree(requester: requester, custodian: custodian, now: now)
    #expect(throws: RappBindingError.WrongPhase) {
      try custodian.beginCpace(
        candidateId: Self.candidate, randomBytes64: Self.random(), nowMonotonicMs: now)
    }
    #expect(custodian.candidateFailed(nowMonotonicMs: now))
    try Self.expectOfferConsumed(by: custodian, now: now + Self.spacing)
  }

  @Test("T_A after the five-second window is refused and frees the slot")
  internal func lateConfirmationIsRefused() throws {
    let custodian = try Self.custodian(code: Self.code)
    let now: UInt64 = 1_000
    let requester = try Self.requester(of: custodian, code: Self.code, at: now)
    let stepThree = try Self.cpaceToStepThree(
      requester: requester, custodian: custodian, now: now)
    #expect(throws: RappBindingError.ProtocolFailure) {
      try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now + Self.attemptWindow)
    }
    #expect(custodian.candidateFailed(nowMonotonicMs: now + Self.attemptWindow))
    try Self.expectOfferConsumed(by: custodian, now: now + Self.attemptWindow)
  }

  @Test("An invalid Y_A is refused before any attempt is admitted")
  internal func invalidStepOneSpendsNoAttempt() throws {
    let custodian = try Self.custodian(code: Self.code)
    let start: UInt64 = 1_000
    for attempt in 0..<Self.repeatedAttempts {
      let now = Self.attemptTime(attempt, from: start)
      try custodian.beginCpace(
        candidateId: Self.candidate, randomBytes64: Self.random(), nowMonotonicMs: now)
      #expect(throws: RappBindingError.ProtocolFailure) {
        try custodian.readCpaceFrame(
          bytes: Data(count: RappCpaceConstants.step1Size), nowMonotonicMs: now)
      }
    }
    try Self.expectOfferConsumed(
      by: custodian, now: Self.attemptTime(Self.repeatedAttempts, from: start))
  }

  @Test("After CPace consumed the offer, a failure ends the ceremony")
  internal func consumedOfferIsNotRestored() throws {
    let custodian = try Self.custodian(code: Self.code)
    let requester = try Self.requester(of: custodian, code: Self.code)
    let now: UInt64 = 1_000
    let stepThree = try Self.cpaceToStepThree(
      requester: requester, custodian: custodian, now: now)
    try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now)
    #expect(custodian.candidateFailed(nowMonotonicMs: now) == false)
    #expect(throws: RappBindingError.WrongPhase) {
      try custodian.beginCpace(
        candidateId: Self.candidate, randomBytes64: Self.random(), nowMonotonicMs: now)
    }
  }

  @Test("The handshake must finish within ten seconds of the handoff")
  internal func handshakeDeadline() throws {
    let custodian = try Self.custodian(code: Self.code)
    let requester = try Self.requester(of: custodian, code: Self.code)
    let now: UInt64 = 1_000
    let stepThree = try Self.cpaceToStepThree(
      requester: requester, custodian: custodian, now: now)
    try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now)
    let late = now + PairingPhaseDeadline.handshakeMilliseconds
    #expect(throws: RappBindingError.ProtocolFailure) {
      try custodian.readHandshakeFrame(
        bytes: try requester.writeHandshakeFrame(nowMonotonicMs: now), nowMonotonicMs: late)
    }
  }
}
