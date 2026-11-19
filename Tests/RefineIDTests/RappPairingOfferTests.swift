// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CardCore
  import Testing

  @testable import RefineIDTestHost

  /// An offer marks the model as offering.
  ///
  /// For as long as the ceremony it started runs; a failed or cancelled
  /// attempt clears the mark. A requester-only device offers nothing.
  @Suite(.serialized)
  internal final class RappPairingOfferTests {
    @MainActor
    @Test
    internal func testAnOfferShowsItsCodeAndMarksTheModelOffering() {
      let model = RappPairingModel()
      model.createOffer(customCode: "7KX4M9")
      guard SupportedCardTransports.servesRemoteCards else {
        #expect(!(model.isOffering))
        #expect((model.phase) == (RappPairingModel.Phase.idle))
        return
      }
      #expect((model.isOffering))
      #expect((model.phase) == (RappPairingModel.Phase.offer("7KX4M9")))
      model.cancel()
      #expect(!(model.isOffering))
      #expect((model.phase) == (RappPairingModel.Phase.idle))
    }

    @MainActor
    @Test
    internal func testAFailedAttemptClearsTheOfferingMark() {
      let model = RappPairingModel()
      model.createOffer(customCode: "7KX4M9")
      model.fail(.reported("ended"))
      #expect(!(model.isOffering))
      #expect((model.phase) == (RappPairingModel.Phase.failed(.reported("ended"))))
    }
  }
#endif
