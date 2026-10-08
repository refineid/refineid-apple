// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP pairing offer, URI, and deadline")
internal struct PairingOfferTests {
  /// Milliseconds the deadline fixture starts at.
  private static let deadlineStart: UInt64 = 10_000

  /// Lifetime the deadline fixture is built with.
  private static let deadlineLifetime: UInt64 = 60_000

  /// RAPP v26.10.1 §4.2 states the KC2 BLE offer's encoded size.
  private static let specifiedBleOfferSize = 400

  private var goldenEncoding: String { expectedOfferEncodingHex.filter { !$0.isWhitespace } }

  @Test("The offer hash matches an independent encoding")
  internal func offerHashMatchesReference() throws {
    #expect(try makeOffer().offerHash().hex == expectedOfferHashHex)
  }

  @Test("The offer encodes to the independent deterministic bytes")
  internal func offerEncodingMatchesReference() throws {
    #expect(try makeOffer().encoded().hex == goldenEncoding)
  }

  @Test("A decoded offer preserves every field")
  internal func decodePreservesEveryField() throws {
    let offer = try makeOffer()
    let decoded = try PairingOffer.decode(try offer.encoded())
    #expect(decoded.offerIdentifier == offer.offerIdentifier)
    #expect(decoded.suites == offer.suites)
    #expect(decoded.profiles == offer.profiles)
    #expect(decoded.transports == offer.transports)
    #expect(decoded.offerLifetimeMilliseconds == offer.offerLifetimeMilliseconds)
    #expect(try decoded.offerHash() == offer.offerHash())
  }

  @Test("The specification's BLE offer encodes to exactly 400 bytes")
  internal func bleExampleOfferSize() throws {
    let offer = try PairingOffer(
      offerIdentifier: filler(0x00, OfferLimit.offerIdentifierSize),
      suites: [RappCpaceConstants.kc2Suite],
      profiles: [
        "fi.refineid.card-status.v1", "fi.refineid.authentication.v1",
        "fi.refineid.document-signing.v1",
      ],
      transports: [
        TransportCandidate(
          profile: "fi.refineid.rapp.ble.v1", candidateIdentifier: "ble-direct-1",
          parameters: ["service_uuid": .text("7E39FD01-A6B5-4D78-9E11-37E28E9545F1")])
      ],
      offerLifetimeMilliseconds: OfferLimit.offerLifetimeMaximumMilliseconds)
    #expect(try offer.encoded().count == Self.specifiedBleOfferSize)
  }

  @Test("A code-derived offer matches the reference identifier")
  internal func codeOfferIdentifier() throws {
    let offer = try PairingOffer.fromCode(
      "7KX4M9", profiles: ["fi.refineid.card-status.v1"],
      transports: [TransportCandidate(profile: "fi.refineid.stream.v1", candidateIdentifier: "s")],
      offerLifetimeMilliseconds: OfferLimit.offerLifetimeMaximumMilliseconds)
    #expect(offer.offerIdentifier.hex == expectedCodeOfferIdentifierHex)
    #expect(offer.suites == [RappCpaceConstants.kc2Suite])
  }

  @Test("Another version, an unknown field and truncation are rejected")
  internal func malformedEncodingsAreRejected() throws {
    let encoded = try makeOffer().encoded()
    #expect(throws: (any Error).self) { _ = try PairingOffer.decode(encoded.dropLast(1)) }
    guard case .map(var map) = try decodeDeterministicCbor(encoded) else {
      Issue.record("offer is not a map")
      return
    }
    map["version"] = .array([.unsigned(26), .unsigned(9), .unsigned(28)])
    #expect(throws: PairingOfferError.unsupportedVersion) {
      _ = try PairingOffer.decode(try WireValue.map(map).encoded())
    }
    map["pairing_secret"] = .bytes(filler(0x02, OfferLimit.offerIdentifierSize))
    #expect(throws: PairingOfferError.unknownField) {
      _ = try PairingOffer.decode(try WireValue.map(map).encoded())
    }
  }

  @Test("An offer without the mandatory suite is rejected")
  internal func offerWithoutMandatorySuiteIsRejected() {
    #expect(throws: (any Error).self) {
      _ = try PairingOffer(
        offerIdentifier: filler(0x01, OfferLimit.offerIdentifierSize),
        suites: ["Noise_XX_25519_ChaChaPoly_SHA256"],
        profiles: ["fi.refineid.card-status.v1"],
        transports: [TransportCandidate(profile: "p", candidateIdentifier: "c")],
        offerLifetimeMilliseconds: Self.deadlineLifetime)
    }
  }

  @Test("A lifetime above the ceiling is rejected")
  internal func lifetimeAboveCeilingIsRejected() {
    #expect(throws: (any Error).self) {
      _ = try PairingOffer(
        offerIdentifier: filler(0x01, OfferLimit.offerIdentifierSize),
        suites: [RappCpaceConstants.kc2Suite],
        profiles: ["fi.refineid.card-status.v1"],
        transports: [TransportCandidate(profile: "p", candidateIdentifier: "c")],
        offerLifetimeMilliseconds: OfferLimit.offerLifetimeMaximumMilliseconds + 1)
    }
  }

  @Test("A deadline is live only inside its interval")
  internal func deadlineIsLiveOnlyInsideItsInterval() throws {
    let deadline = try PairingOfferDeadline(
      offer: try makeOffer(), startedAtMilliseconds: Self.deadlineStart)
    #expect(!deadline.isLive(nowMilliseconds: Self.deadlineStart - 1))
    #expect(deadline.isLive(nowMilliseconds: Self.deadlineStart))
    #expect(deadline.isLive(nowMilliseconds: Self.deadlineStart + Self.deadlineLifetime - 1))
    #expect(!deadline.isLive(nowMilliseconds: Self.deadlineStart + Self.deadlineLifetime))
  }

  @Test("A deadline that would overflow is rejected")
  internal func deadlineOverflowIsRejected() throws {
    let offer = try makeOffer()
    #expect(throws: (any Error).self) {
      _ = try PairingOfferDeadline(offer: offer, startedAtMilliseconds: UInt64.max)
    }
  }
}
