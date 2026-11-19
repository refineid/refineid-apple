// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import Testing

/// An offer lives five minutes from its creation (RAPP v26.11.8 §3.3 item 7).
@Suite(.serialized)
internal final class RappOfferExpiryTests {
  private static let startedAt: UInt64 = 1_000
  private static let offerLifetime = rappOfferTtlMs()

  @Test
  internal func testOfferExpiresAtItsMonotonicDeadline() throws {
    #expect(throws: Never.self) { try begin(at: Self.startedAt + Self.offerLifetime - 1) }
    assertOfferExpired { try begin(at: Self.startedAt + Self.offerLifetime) }
  }

  private func begin(at now: UInt64) throws {
    let transportProfile = rappStreamProfileName()
    let bridge = try RappPairingBridge.custodianOffer(
      pairingCode: "246813",
      offerId: try RappPlatformEntropy().offerID(),
      profiles: rappCredentialProfiles(),
      transportProfiles: [transportProfile],
      startedAtMonotonicMs: Self.startedAt
    )
    try bridge.beginCpace(
      candidateId: try #require(rappCandidateIdentifier(transportProfile: transportProfile)),
      randomBytes64: try RappPlatformEntropy().cpaceRandom(),
      nowMonotonicMs: now)
  }

  private func assertOfferExpired(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () throws -> Void
  ) {
    #expect(throws: RappBindingError.OfferExpired, sourceLocation: sourceLocation) {
      try operation()
    }
  }
}
