// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import XCTest

/// An offer lives five minutes from its creation (RAPP v26.10.22 §3.3 item 7).
internal final class RappOfferExpiryTests: XCTestCase {
  private static let startedAt: UInt64 = 1_000
  private static let offerLifetime = rappOfferTtlMs()

  internal func testOfferExpiresAtItsMonotonicDeadline() throws {
    XCTAssertNoThrow(try begin(at: Self.startedAt + Self.offerLifetime - 1))
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
      candidateId: try XCTUnwrap(rappCandidateIdentifier(transportProfile: transportProfile)),
      randomBytes64: try RappPlatformEntropy().cpaceRandom(),
      nowMonotonicMs: now)
  }

  private func assertOfferExpired(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () throws -> Void
  ) {
    XCTAssertThrowsError(try operation(), file: file, line: line) { error in
      guard case RappBindingError.OfferExpired = error else {
        XCTFail("Expected OfferExpired, got \(error)", file: file, line: line)
        return
      }
    }
  }
}
