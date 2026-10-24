// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

@testable import RefineIDTestHost

/// An offer marks the model as offering for as long as the ceremony it
/// started runs; a failed or cancelled attempt clears the mark.
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
    model.fail(.reported("ended"))
    XCTAssertFalse(model.isOffering)
    XCTAssertEqual(model.phase, RappPairingModel.Phase.failed(.reported("ended")))
  }
}
