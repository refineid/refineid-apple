// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.22 a requester's tries of one code over real pairing bridges")
internal struct RappPairingCandidatesTests {
  /// The code the right phone shows and the user types.
  private static let typedCode = "7KX4M9"
  /// The code the other phone in pairing mode shows.
  private static let otherCode = "3HQ8TW"
  private static let candidate = TransportRegistry.streamCandidateIdentifier
  private static let now: UInt64 = 1_000

  /// A phone in pairing mode showing `code`, serving its offer on `transports`.
  private static func custodian(
    showing code: String, transports: [String]
  ) throws -> RappPairingBridge {
    try RappPairingBridge.custodianOffer(
      pairingCode: code, offerId: randomBytes(OfferLimit.offerIdentifierSize),
      profiles: ProfileName.allCases.map(\.rawValue), transportProfiles: transports,
      startedAtMonotonicMs: now)
  }

  /// The requester's side of a connection to `custodian` over `transport`.
  private static func requester(
    of custodian: RappPairingBridge, transport: String
  ) throws -> RappPairingBridge {
    try RappPairingBridge.bootstrapOffer(
      encodedOffer: try custodian.encodedOffer(), transportProfile: transport,
      pairingCode: typedCode, startedAtMonotonicMs: now)
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

    #expect(try candidates.nextEndpoint() == "other")
    let first = try Self.requester(of: other, transport: streamProfile)
    #expect(try candidates.beginTry(first))
    #expect(throws: RappBindingError.ProtocolFailure) {
      try Self.tryCode(requester: first, custodian: other)
    }
    #expect(try candidates.closed() == .tryNext)

    #expect(try candidates.nextEndpoint() == "right")
    let second = try Self.requester(of: right, transport: streamProfile)
    #expect(try candidates.beginTry(second))
    try Self.tryCode(requester: second, custodian: right)
    try candidates.accepted()
    #expect(throws: RappBindingError.WrongPhase) { _ = try candidates.nextEndpoint() }
  }

  @Test("A phone found on two transports receives one guess")
  internal func aPhoneFoundTwiceGetsOneGuess() throws {
    let phone = try Self.custodian(
      showing: Self.otherCode, transports: [streamProfile, RappBleGattProfile.name])
    let candidates = RappPairingCandidates<String>()
    candidates.found("stream")
    candidates.found("ble")

    _ = try candidates.nextEndpoint()
    let first = try Self.requester(of: phone, transport: streamProfile)
    #expect(try candidates.beginTry(first))
    #expect(throws: RappBindingError.ProtocolFailure) {
      try Self.tryCode(requester: first, custodian: phone)
    }
    #expect(phone.candidateFailed(nowMonotonicMs: Self.now), "the phone keeps its offer")
    #expect(try candidates.closed() == .tryNext)

    _ = try candidates.nextEndpoint()
    let again = try Self.requester(of: phone, transport: RappBleGattProfile.name)
    #expect(try candidates.beginTry(again) == false)
    #expect(try candidates.closed() == .notAccepted)
  }

  @Test("Only a requester's offer awaiting CPace begins a try")
  internal func onlyAnUntriedRequesterOffer() throws {
    let custodian = try Self.custodian(showing: Self.typedCode, transports: [streamProfile])
    let candidates = RappPairingCandidates<String>()
    candidates.found("phone")
    _ = try candidates.nextEndpoint()
    #expect(throws: RappBindingError.WrongPhase) { _ = try candidates.beginTry(custodian) }
    let requester = try Self.requester(of: custodian, transport: streamProfile)
    try requester.beginCpace(
      candidateId: Self.candidate, randomBytes64: randomBytes(RappCpaceConstants.wideScalarSize),
      nowMonotonicMs: Self.now)
    #expect(throws: RappBindingError.WrongPhase) { _ = try candidates.beginTry(requester) }
  }
}
