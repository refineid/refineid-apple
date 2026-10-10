// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.10.9 pairing offer and deadline (section 4.2)")
internal struct PairingOfferTests {
  /// Milliseconds the deadline fixture starts at.
  private static let deadlineStart: UInt64 = 10_000

  @Test("Offers encode to the corpus bootstrap bytes on every transport")
  internal func offersReplayTheCorpus() throws {
    let vectors = try CorpusFile.conformance(filePath: #filePath).pairingOffer
    #expect(!vectors.isEmpty)
    for vector in vectors {
      let offer = try PairingOffer.create(
        offerIdentifier: try Data(hex: vector.offerIdHex), profiles: vector.profiles,
        transportProfiles: vector.transportProfiles)
      let encoded = try offer.encoded()
      #expect(encoded.hex == vector.encodedHex, "\(vector.name) bytes")
      #expect(encoded.count == vector.encodedLength, "\(vector.name) length")
      #expect(try offer.offerHash().hex == vector.offerHashHex, "\(vector.name) hash")
      let decoded = try PairingOffer.decode(try Data(hex: vector.encodedHex))
      #expect(try decoded.encoded() == encoded, "\(vector.name) round trip")
    }
  }

  @Test("Transports are listed in byte order whatever order they are named in")
  internal func transportsAreSorted() throws {
    let offer = try PairingOffer.create(
      offerIdentifier: filler(0x01, OfferLimit.offerIdentifierSize),
      profiles: ["fi.refineid.card-status.v1"],
      transportProfiles: [streamProfile, RappBleGattProfile.name])
    #expect(offer.transports.map(\.profile) == [RappBleGattProfile.name, streamProfile])
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

  @Test("Another version, an unknown field and truncation are rejected")
  internal func malformedEncodingsAreRejected() throws {
    let encoded = try makeOffer().encoded()
    #expect(throws: (any Error).self) { _ = try PairingOffer.decode(encoded.dropLast(1)) }
    guard case .map(var map) = try decodeDeterministicCbor(encoded) else {
      Issue.record("offer is not a map")
      return
    }
    map["version"] = .array([.unsigned(26), .unsigned(10), .unsigned(1)])
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
        transports: [try #require(TransportRegistry.entry(for: streamProfile))],
        offerLifetimeMilliseconds: OfferLimit.offerLifetimeMilliseconds)
    }
  }

  @Test("Any lifetime but the fixed 60 seconds is rejected")
  internal func otherLifetimesAreRejected() throws {
    let entry = try #require(TransportRegistry.entry(for: streamProfile))
    for lifetime in [
      OfferLimit.offerLifetimeMilliseconds - 1, OfferLimit.offerLifetimeMilliseconds + 1,
    ] {
      #expect(throws: PairingOfferError.invalidLifetime) {
        _ = try PairingOffer(
          offerIdentifier: filler(0x01, OfferLimit.offerIdentifierSize),
          suites: [RappCpaceConstants.kc2Suite],
          profiles: ["fi.refineid.card-status.v1"],
          transports: [entry],
          offerLifetimeMilliseconds: lifetime)
      }
    }
  }

  @Test("Unregistered, misordered or altered transport entries are rejected")
  internal func transportEntriesAreRegistered() throws {
    let stream = try #require(TransportRegistry.entry(for: streamProfile))
    let ble = RappBleGattProfile.candidate
    var withEndpoints = stream
    withEndpoints.parameters = ["endpoints": .array([.text("192.0.2.1:47110")])]
    for transports in [
      [TransportCandidate(profile: "p", candidateIdentifier: "c")],
      [stream, ble],
      [withEndpoints],
      [ble, ble],
    ] {
      #expect(throws: PairingOfferError.invalidTransport) {
        _ = try PairingOffer(
          offerIdentifier: filler(0x01, OfferLimit.offerIdentifierSize),
          suites: [RappCpaceConstants.kc2Suite],
          profiles: ["fi.refineid.card-status.v1"],
          transports: transports,
          offerLifetimeMilliseconds: OfferLimit.offerLifetimeMilliseconds)
      }
    }
  }

  @Test("A deadline is live only inside its interval")
  internal func deadlineIsLiveOnlyInsideItsInterval() throws {
    let lifetime = OfferLimit.offerLifetimeMilliseconds
    let deadline = try PairingOfferDeadline(
      offer: try makeOffer(), startedAtMilliseconds: Self.deadlineStart)
    #expect(!deadline.isLive(nowMilliseconds: Self.deadlineStart - 1))
    #expect(deadline.isLive(nowMilliseconds: Self.deadlineStart))
    #expect(deadline.isLive(nowMilliseconds: Self.deadlineStart + lifetime - 1))
    #expect(!deadline.isLive(nowMilliseconds: Self.deadlineStart + lifetime))
  }

  @Test("A deadline that would overflow is rejected")
  internal func deadlineOverflowIsRejected() throws {
    let offer = try makeOffer()
    #expect(throws: (any Error).self) {
      _ = try PairingOfferDeadline(offer: offer, startedAtMilliseconds: UInt64.max)
    }
  }
}
