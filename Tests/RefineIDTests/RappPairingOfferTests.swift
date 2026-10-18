// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

@testable import RefineID

/// An offer marks the model as offering for as long as the ceremony it
/// started runs; ending the attempt, however it ends, clears the mark.
internal final class RappPairingOfferTests: XCTestCase {
  @MainActor
  internal func testAnOfferShowsItsCodeAndMarksTheModelOffering() {
    let model = RappPairingModel()
    model.createOffer(customCode: "7KX4M9")
    XCTAssertTrue(model.isOffering)
    XCTAssertEqual(model.phase, RappPairingModel.Phase.offer("7KX4M9"))
    model.cancel()
    XCTAssertFalse(model.isOffering)
    XCTAssertEqual(model.phase, RappPairingModel.Phase.idle)
  }

  @MainActor
  internal func testAFailedAttemptClearsTheOfferingMark() {
    let model = RappPairingModel()
    model.createOffer(customCode: "7KX4M9")
    model.fail("ended")
    XCTAssertFalse(model.isOffering)
    XCTAssertEqual(model.phase, RappPairingModel.Phase.failed("ended"))
  }
}
