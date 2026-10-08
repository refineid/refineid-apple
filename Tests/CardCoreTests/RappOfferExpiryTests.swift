// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
import XCTest

internal final class RappOfferExpiryTests: XCTestCase {
  private static let cpaceRandomByteCount = 64

  internal func testOfferExpiresAtItsMonotonicDeadline() throws {
    XCTAssertNoThrow(try begin(at: 1_099))
    assertOfferExpired { try begin(at: 1_100) }
  }

  private func begin(at now: UInt64) throws {
    let bridge = try RappPairingBridge.codeOffer(
      role: .proxy,
      pairingCode: "246813",
      profiles: ["fi.refineid.card-status.v1"],
      transports: [
        RappTransportCandidate(
          profile: "local-quic-v1",
          candidateId: "candidate",
          parametersCbor: Data([0xa0])
        )
      ],
      offerTtlMs: 100,
      startedAtMonotonicMs: 1_000
    )
    try bridge.beginCpace(
      candidateId: "candidate",
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
