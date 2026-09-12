// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

@testable import RefineID

/// A `--pretend-paired` launch starts the pairing row paired, and
/// revoking it returns the row to Connect.
internal final class PretendPairedTests: XCTestCase {
  @MainActor
  internal func testPretendPairingStartsAbsent() {
    let model = RappPairingModel()
    XCTAssertFalse(model.pretendPaired)
    XCTAssertFalse(model.hasActivePairs)
  }

  @MainActor
  internal func testRevokingClearsPretendPairing() {
    let model = RappPairingModel()
    model.pretendPaired = true
    XCTAssertTrue(model.hasActivePairs)
    model.revokeAll()
    XCTAssertFalse(model.pretendPaired)
    XCTAssertFalse(model.hasActivePairs)
  }
}
