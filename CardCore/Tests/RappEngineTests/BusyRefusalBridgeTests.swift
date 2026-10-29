// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.29 a custodian that cannot admit an attempt answers busy (section 4.2)")
internal struct BusyRefusalBridgeTests {
  private static let code = "7KX4M9"
  private static let wrongCode = "3HQ8TW"
  private static let candidate = TransportRegistry.streamCandidateIdentifier
  private static let start: UInt64 = 1_000
  private static let window = CpaceAttemptSlot.attemptWindowMilliseconds
  private static let spacing = RappPreAuthenticationLimiter.minimumSpacingMilliseconds
  /// A point inside the spacing, after a refused or failed start.
  private static let partOfTheSpacing: UInt64 = 100
  /// What the platform's connection-accept limiter still has to wait.
  private static let limiterWait: UInt64 = 300
  /// More wrong codes than any per-offer count would admit.
  private static let repeatedAttempts = 8

  private static func custodian() throws -> RappPairingBridge {
    try RappPairingBridge.custodianOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: ProfileName.allCases.map(\.rawValue), transportProfiles: [streamProfile],
      startedAtMonotonicMs: start)
  }

  private static func requester(
    of custodian: RappPairingBridge, code: String, at time: UInt64
  ) throws -> RappPairingBridge {
    try RappPairingBridge.bootstrapOffer(
      bootstrap: try custodian.bootstrapBytes(nowMonotonicMs: time),
      transportProfile: streamProfile, pairingCode: code, startedAtMonotonicMs: time)
  }

  /// Runs CPace through the custodian's step 2 at `time`, admitting the
  /// attempt; returns step 2.
  private static func admitAttempt(
    requester: RappPairingBridge, custodian: RappPairingBridge, at time: UInt64
  ) throws -> Data {
    let random = randomBytes(RappCpaceConstants.wideScalarSize)
    try requester.beginCpace(candidateId: candidate, randomBytes64: random, nowMonotonicMs: time)
    try custodian.beginCpace(candidateId: candidate, randomBytes64: random, nowMonotonicMs: time)
    try custodian.readCpaceFrame(
      bytes: try requester.writeCpaceFrame(nowMonotonicMs: time), nowMonotonicMs: time)
    return try custodian.writeCpaceFrame(nowMonotonicMs: time)
  }

  /// The wait the custodian's bootstrap answer asks for at `time`, or nil
  /// when it serves its offer.
  private static func bootstrapWait(_ custodian: RappPairingBridge, at time: UInt64) throws
    -> UInt64?
  {
    let answer = try custodian.bootstrapBytes(nowMonotonicMs: time)
    do {
      _ = try RappPairingBridge.bootstrapOffer(
        bootstrap: answer, transportProfile: streamProfile, pairingCode: code,
        startedAtMonotonicMs: time)
      return nil
    } catch RappBindingError.CustodianBusy {
      return try rappPairingBusyRetryAfterMs(answer)
    }
  }

  @Test("An active attempt answers busy with the larger of its time and the spacing's")
  internal func anActiveAttemptAnswersBusy() throws {
    let custodian = try Self.custodian()
    let first = try Self.requester(of: custodian, code: Self.code, at: Self.start)
    _ = try Self.admitAttempt(requester: first, custodian: custodian, at: Self.start)
    #expect(!custodian.admitsAttempt(nowMonotonicMs: Self.start + Self.spacing))
    #expect(
      try Self.bootstrapWait(custodian, at: Self.start + Self.spacing)
        == Self.window - Self.spacing)
    #expect(
      try Self.bootstrapWait(custodian, at: Self.start + Self.partOfTheSpacing)
        == Self.window - Self.partOfTheSpacing)
  }

  @Test("Inside the spacing after a failed attempt the custodian answers busy for the rest")
  internal func insideTheSpacingTheCustodianAnswersBusy() throws {
    let custodian = try Self.custodian()
    let first = try Self.requester(of: custodian, code: Self.wrongCode, at: Self.start)
    let stepTwo = try Self.admitAttempt(requester: first, custodian: custodian, at: Self.start)
    #expect(throws: RappBindingError.ProtocolFailure) {
      try first.readCpaceFrame(bytes: stepTwo, nowMonotonicMs: Self.start)
    }
    #expect(custodian.candidateFailed(nowMonotonicMs: Self.start))
    let inside = Self.start + Self.partOfTheSpacing
    #expect(try Self.bootstrapWait(custodian, at: inside) == Self.spacing - Self.partOfTheSpacing)
    #expect(!custodian.admitsAttempt(nowMonotonicMs: inside))
    #expect(throws: RappBindingError.RateLimited) {
      try custodian.beginCpace(
        candidateId: Self.candidate,
        randomBytes64: randomBytes(RappCpaceConstants.wideScalarSize), nowMonotonicMs: inside)
    }
    #expect(
      try rappPairingBusyRetryAfterMs(
        try custodian.busyBytes(nowMonotonicMs: inside, spacingWaitMs: 0))
        == Self.spacing - Self.partOfTheSpacing)
    #expect(try Self.bootstrapWait(custodian, at: Self.start + Self.spacing) == nil)
    #expect(custodian.admitsAttempt(nowMonotonicMs: Self.start + Self.spacing))
  }

  @Test("A step 1 the custodian cannot admit is answered busy in place of step 2")
  internal func busyInPlaceOfStepTwo() throws {
    let custodian = try Self.custodian()
    let first = try Self.requester(of: custodian, code: Self.code, at: Self.start)
    let second = try Self.requester(of: custodian, code: Self.code, at: Self.start)
    _ = try Self.admitAttempt(requester: first, custodian: custodian, at: Self.start)
    let later = Self.start + Self.partOfTheSpacing
    try second.beginCpace(
      candidateId: Self.candidate, randomBytes64: randomBytes(RappCpaceConstants.wideScalarSize),
      nowMonotonicMs: later)
    _ = try second.writeCpaceFrame(nowMonotonicMs: later)
    #expect(throws: RappBindingError.WrongPhase) {
      try custodian.beginCpace(
        candidateId: Self.candidate,
        randomBytes64: randomBytes(RappCpaceConstants.wideScalarSize), nowMonotonicMs: later)
    }
    let busy = try custodian.busyBytes(nowMonotonicMs: later, spacingWaitMs: 0)
    #expect(try rappPairingBusyRetryAfterMs(busy) == Self.window - Self.partOfTheSpacing)
    #expect(throws: RappBindingError.CustodianBusy) {
      try second.readCpaceFrame(bytes: busy, nowMonotonicMs: later)
    }
    #expect(second.requesterOfferAwaitingCpace() != nil, "the requester keeps the offer")
  }

  @Test("A connection the platform's limiter refused is answered with the limiter's wait")
  internal func theLimiterWaitIsAnswered() throws {
    let custodian = try Self.custodian()
    let limiter = RappPreAuthenticationLimiter()
    #expect(limiter.admit(nowMonotonicMs: Self.start))
    let refusedAt = Self.start + Self.spacing - Self.limiterWait
    #expect(!limiter.admit(nowMonotonicMs: refusedAt))
    let wait = limiter.waitMs(nowMonotonicMs: refusedAt)
    #expect(wait == Self.limiterWait)
    let busy = try custodian.busyBytes(nowMonotonicMs: refusedAt, spacingWaitMs: wait)
    #expect(try rappPairingBusyRetryAfterMs(busy) == Self.limiterWait)
  }

  @Test("Only a live custodian offer answers busy")
  internal func busyNeedsALiveCustodianOffer() throws {
    let custodian = try Self.custodian()
    let requester = try Self.requester(of: custodian, code: Self.code, at: Self.start)
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try requester.busyBytes(nowMonotonicMs: Self.start, spacingWaitMs: 0)
    }
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try requester.bootstrapBytes(nowMonotonicMs: Self.start)
    }
    #expect(!requester.admitsAttempt(nowMonotonicMs: Self.start))
    #expect(throws: RappBindingError.InvalidInput) {
      _ = try rappPairingBusyRetryAfterMs(try custodian.bootstrapBytes(nowMonotonicMs: Self.start))
    }
    #expect(throws: RappBindingError.OfferExpired) {
      _ = try custodian.busyBytes(
        nowMonotonicMs: Self.start + OfferLimit.offerLifetimeMilliseconds, spacingWaitMs: 0)
    }
  }

  @Test("Wrong codes never make the custodian busy once their attempts ended")
  internal func wrongCodesLeaveNoBusy() throws {
    let custodian = try Self.custodian()
    let attempts = Self.repeatedAttempts
    for attempt in 0..<attempts {
      let time = Self.start + UInt64(attempt) * Self.spacing
      #expect(try Self.bootstrapWait(custodian, at: time) == nil, "attempt \(attempt)")
      let requester = try Self.requester(of: custodian, code: Self.wrongCode, at: time)
      let stepTwo = try Self.admitAttempt(requester: requester, custodian: custodian, at: time)
      #expect(throws: RappBindingError.ProtocolFailure) {
        try requester.readCpaceFrame(bytes: stepTwo, nowMonotonicMs: time)
      }
      #expect(custodian.candidateFailed(nowMonotonicMs: time))
    }
    #expect(
      try Self.bootstrapWait(custodian, at: Self.start + UInt64(attempts) * Self.spacing) == nil)
  }
}
