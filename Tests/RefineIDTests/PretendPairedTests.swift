// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import Testing

  @testable import RefineIDTestHost

  /// The pairing row starts unpaired unless a launch pretends otherwise.
  @Suite(.serialized)
  internal final class PretendPairedTests {
    @MainActor
    @Test
    internal func testPretendPairingStartsAbsent() {
      let model = RappPairingModel()
      #expect(!(model.pretendPaired))
      #expect(!(model.hasActivePairs))
    }
  }
#endif
