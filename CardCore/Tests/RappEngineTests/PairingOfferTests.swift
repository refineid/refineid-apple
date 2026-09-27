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

  private var goldenUri: String { expectedOfferUri.filter { !$0.isWhitespace } }

  @Test("The offer hash matches the reference implementation")
  internal func offerHashMatchesReference() throws {
    let hash = try makeOffer().offerHash().hex
    #expect(hash == expectedOfferHashHex)
  }

  @Test("The offer URI matches the reference implementation")
  internal func offerUriMatchesReference() throws {
    let uri = try makeOffer().uri()
    #expect(uri == goldenUri)
  }

  @Test("A URI round trip preserves every field")
  internal func uriRoundTripPreservesEveryField() throws {
    let offer = try makeOffer()
    let decoded = try PairingOffer.from(uri: try offer.uri())
    #expect(decoded.offerIdentifier == offer.offerIdentifier)
    #expect(decoded.pairingSecret == offer.pairingSecret)
    #expect(decoded.suites == offer.suites)
    #expect(decoded.profiles == offer.profiles)
    #expect(decoded.transports == offer.transports)
    #expect(decoded.offerLifetimeMilliseconds == offer.offerLifetimeMilliseconds)
    #expect(try decoded.offerHash() == offer.offerHash())
  }

  @Test("A single-candidate offer round-trips")
  internal func singleCandidateOfferRoundTrips() throws {
    let single = try PairingOffer(
      offerIdentifier: filler(0x0a, OfferLimit.offerIdentifierSize),
      pairingSecret: filler(0x0b, OfferLimit.pairingSecretSize),
      suites: [mandatoryPairingSuite, "Noise_XX_25519_ChaChaPoly_SHA256"],
      profiles: ["fi.refineid.document-signing.v1"],
      transports: [TransportCandidate(profile: "local-quic-v1", candidateIdentifier: "candidate")],
      offerLifetimeMilliseconds: OfferLimit.offerLifetimeMaximumMilliseconds)
    #expect(try PairingOffer.from(uri: single.uri()).transports == single.transports)
  }

  @Test("A wrong scheme prefix is rejected")
  internal func wrongSchemeIsRejected() throws {
    let uri = goldenUri
    #expect(throws: (any Error).self) {
      _ = try PairingOffer.from(uri: "http:" + String(uri.dropFirst(5)))
    }
  }

  @Test("An invalid base64url character is rejected")
  internal func invalidBase64UrlCharacterIsRejected() {
    #expect(throws: (any Error).self) { _ = try PairingOffer.from(uri: "rapp:!!!!") }
  }

  @Test("base64url padding is rejected")
  internal func base64UrlPaddingIsRejected() {
    #expect(throws: (any Error).self) { _ = try PairingOffer.from(uri: "rapp:qGZzY2hlbWU=") }
  }

  @Test("Truncated payload bytes are rejected")
  internal func truncatedPayloadIsRejected() throws {
    let uri = goldenUri
    #expect(throws: (any Error).self) { _ = try PairingOffer.from(uri: String(uri.dropLast(8))) }
  }

  @Test("An empty payload is rejected")
  internal func emptyPayloadIsRejected() {
    #expect(throws: (any Error).self) { _ = try PairingOffer.from(uri: "rapp:") }
  }

  @Test("An offer without the mandatory suite is rejected")
  internal func offerWithoutMandatorySuiteIsRejected() {
    #expect(throws: (any Error).self) {
      _ = try PairingOffer(
        offerIdentifier: filler(0x01, OfferLimit.offerIdentifierSize),
        pairingSecret: filler(0x02, OfferLimit.pairingSecretSize),
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
        pairingSecret: filler(0x02, OfferLimit.pairingSecretSize),
        suites: [mandatoryPairingSuite],
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
