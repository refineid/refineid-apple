// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.9 pairing bridge: CPace KC2, attempt accounting, ceremony")
internal struct PairingBridgeTests {
  private static let code = "7KX4M9"
  private static let wrongCode = "7KX4M8"
  private static let candidate = "stream-1"
  private static let profiles = [
    "fi.refineid.card-status.v1", "fi.refineid.authentication.v1",
    "fi.refineid.document-signing.v1",
  ]
  private static let lifetime: UInt64 = 60_000
  private static let attemptWindow = CpaceAttemptLedger.attemptWindowMilliseconds

  /// The custodian's offer over the stream transport.
  private static func custodian(code: String) throws -> RappPairingBridge {
    try RappPairingBridge.custodianOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: profiles, transportProfiles: [streamProfile], startedAtMonotonicMs: 0)
  }

  /// The requester's side, from the offer the custodian serves.
  private static func requester(
    of custodian: RappPairingBridge, code: String
  ) throws -> RappPairingBridge {
    try RappPairingBridge.bootstrapOffer(
      encodedOffer: try custodian.encodedOffer(), transportProfile: streamProfile,
      pairingCode: code, startedAtMonotonicMs: 0)
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

    let requesterRecord = try requester.finishPairing(createdAtMs: 0, nowMonotonicMs: now)
    let custodianRecord = try custodian.finishPairing(createdAtMs: 0, nowMonotonicMs: now)
    #expect(requesterRecord.metadata().pairId == custodianRecord.metadata().pairId)
    #expect(requesterRecord.metadata().profiles == custodianRecord.metadata().profiles)
    #expect(custodian.candidateFailed(nowMonotonicMs: now) == false)
  }

  @Test("Three wrong codes destroy the custodian's offer")
  internal func threeWrongCodesExhaustTheOffer() throws {
    let custodian = try Self.custodian(code: Self.code)
    let now: UInt64 = 1_000
    for attempt in 1...CpaceAttemptLedger.maximumAttempts {
      let requester = try Self.requester(of: custodian, code: Self.wrongCode)
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
      let restored = custodian.candidateFailed(nowMonotonicMs: now)
      #expect(restored == (attempt < CpaceAttemptLedger.maximumAttempts))
    }
    #expect(custodian.attemptsExhausted())
    #expect(throws: RappBindingError.WrongPhase) {
      try custodian.beginCpace(
        candidateId: Self.candidate, randomBytes64: Self.random(), nowMonotonicMs: now)
    }
  }

  @Test("A forged T_A spends the attempt; the third ends the offer")
  internal func forgedTagsExhaustTheOffer() throws {
    let custodian = try Self.custodian(code: Self.code)
    let now: UInt64 = 1_000
    for attempt in 1...CpaceAttemptLedger.maximumAttempts {
      let requester = try Self.requester(of: custodian, code: Self.code)
      var stepThree = try Self.cpaceToStepThree(
        requester: requester, custodian: custodian, now: now)
      stepThree[stepThree.startIndex] ^= 1
      let expected: RappBindingError =
        attempt < CpaceAttemptLedger.maximumAttempts ? .ProtocolFailure : .AttemptsExhausted
      #expect(throws: expected) {
        try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now)
      }
    }
    #expect(custodian.attemptsExhausted())
  }

  @Test("T_A after the five-second window is refused and spends the attempt")
  internal func lateConfirmationIsRefused() throws {
    let custodian = try Self.custodian(code: Self.code)
    let requester = try Self.requester(of: custodian, code: Self.code)
    let now: UInt64 = 1_000
    let stepThree = try Self.cpaceToStepThree(
      requester: requester, custodian: custodian, now: now)
    #expect(throws: RappBindingError.ProtocolFailure) {
      try custodian.readCpaceFrame(bytes: stepThree, nowMonotonicMs: now + Self.attemptWindow)
    }
    #expect(!custodian.attemptsExhausted())
    #expect(custodian.candidateFailed(nowMonotonicMs: now + Self.attemptWindow))
  }

  @Test("An invalid Y_A is refused before any attempt is admitted")
  internal func invalidStepOneSpendsNoAttempt() throws {
    let custodian = try Self.custodian(code: Self.code)
    let now: UInt64 = 1_000
    for _ in 0...CpaceAttemptLedger.maximumAttempts {
      try custodian.beginCpace(
        candidateId: Self.candidate, randomBytes64: Self.random(), nowMonotonicMs: now)
      #expect(throws: RappBindingError.ProtocolFailure) {
        try custodian.readCpaceFrame(
          bytes: Data(count: RappCpaceConstants.step1Size), nowMonotonicMs: now)
      }
    }
    #expect(!custodian.attemptsExhausted())
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
