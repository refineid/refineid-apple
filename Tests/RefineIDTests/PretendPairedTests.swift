// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import XCTest

  @testable import RefineIDTestHost

  /// The pairing row starts unpaired unless a launch pretends otherwise.
  internal final class PretendPairedTests: XCTestCase {
    @MainActor
    internal func testPretendPairingStartsAbsent() {
      let model = RappPairingModel()
      XCTAssertFalse(model.pretendPaired)
      XCTAssertFalse(model.hasActivePairs)
    }
  }
#endif
