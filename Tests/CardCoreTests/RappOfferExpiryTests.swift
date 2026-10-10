// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
import XCTest

internal final class RappOfferExpiryTests: XCTestCase {
  private static let cpaceRandomByteCount = 64
  private static let offerIdentifierByteCount = 32
  private static let startedAt: UInt64 = 1_000
  private static let offerLifetime: UInt64 = 60_000

  internal func testOfferExpiresAtItsMonotonicDeadline() throws {
    XCTAssertNoThrow(try begin(at: Self.startedAt + Self.offerLifetime - 1))
    assertOfferExpired { try begin(at: Self.startedAt + Self.offerLifetime) }
  }

  private func begin(at now: UInt64) throws {
    let transportProfile = rappStreamProfileName()
    let bridge = try RappPairingBridge.custodianOffer(
      pairingCode: "246813",
      offerId: Data(repeating: 0x10, count: Self.offerIdentifierByteCount),
      profiles: ["fi.refineid.card-status.v1"],
      transportProfiles: [transportProfile],
      startedAtMonotonicMs: Self.startedAt
    )
    try bridge.beginCpace(
      candidateId: try XCTUnwrap(rappCandidateIdentifier(transportProfile: transportProfile)),
      randomBytes64: Data(repeating: 0x11, count: Self.cpaceRandomByteCount),
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
