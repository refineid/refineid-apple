// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// Which document controls the Mac window shows with and without a
  /// card or phone that can sign.
  @Suite
  internal struct StatusDocumentControlsTests {
    private static let documents = [URL(filePath: "/documents/contract.pdf")]

    /// The controls for one window state.
    private static func controls(
      _ availability: LoginIdentityModel.Availability,
      queued: [URL],
      signing working: Bool,
      readingCard: Bool = false,
      failureShown: Bool = false
    ) -> StatusDocumentControls {
      StatusDocumentControls(
        availability: availability, queued: queued, signing: working,
        readingCard: readingCard, failureShown: failureShown)
    }

    /// No card, nothing listed: the identity row still asks for a
    /// reader above the drop area, nothing about signing shows, and
    /// Verify is there but cannot run.
    @Test
    internal func withoutACardAndNothingListedOnlyTheReaderRowAndDropArea() {
      let controls = Self.controls(.noCard, queued: [], signing: false)
      #expect(controls.showsIdentity)
      #expect(!controls.offersSigning)
      #expect(!controls.verifyEnabled)
    }

    /// No card, documents listed: the reader row steps aside, nothing
    /// about signing shows, and Verify runs.
    @Test
    internal func withoutACardListedDocumentsAreForVerifyingOnly() {
      let controls = Self.controls(.noCard, queued: Self.documents, signing: false)
      #expect(!controls.showsIdentity)
      #expect(!controls.offersSigning)
      #expect(controls.verifyEnabled)
    }

    /// A card or a paired phone's identity offers the identity row,
    /// the signing panel and Verify together.
    @Test
    internal func withACardSigningAndVerifyingAreBothOffered() {
      for availability in [LoginIdentityModel.Availability.ready, .cardWithoutIdentity] {
        let controls = Self.controls(availability, queued: Self.documents, signing: false)
        #expect(controls.showsIdentity)
        #expect(controls.offersSigning)
        #expect(controls.verifyEnabled)
      }
      let empty = Self.controls(.ready, queued: [], signing: false)
      #expect(empty.showsIdentity)
      #expect(empty.offersSigning)
      #expect(!empty.verifyEnabled)
    }

    /// While a signature runs Verify waits, and the signing panel stays
    /// even if the card's publication drops for a moment.
    @Test
    internal func whileSigningVerifyWaitsAndThePanelStays() {
      let controls = Self.controls(.noCard, queued: Self.documents, signing: true)
      #expect(controls.showsIdentity)
      #expect(controls.offersSigning)
      #expect(!controls.verifyEnabled)
    }

    /// The button bar holds Verify and the default Sign with a card or
    /// phone, and Verify alone without one.
    @Test
    internal func theButtonBarOffersSignOnlyWhenSomethingCanSign() {
      let withCard = Self.controls(.ready, queued: Self.documents, signing: false)
      let withoutCard = Self.controls(.noCard, queued: Self.documents, signing: false)
      let emptyWithoutCard = Self.controls(.noCard, queued: [], signing: false)

      #expect(withCard.actions == [.verify, .sign])
      #expect(withoutCard.actions == [.verify])
      #expect(emptyWithoutCard.actions.isEmpty)
    }

    /// With nothing listed neither button could act, so the bar shows
    /// none, with a card or phone or without one.
    @Test
    internal func anEmptyListShowsNoButtons() {
      #expect(Self.controls(.ready, queued: [], signing: false).actions.isEmpty)
      #expect(Self.controls(.noCard, queued: [], signing: false).actions.isEmpty)
    }

    /// A card read for the stamp keeps the signing panel and Sign
    /// through a momentary loss of the card's publication.
    @Test
    internal func whileReadingTheCardThePanelStays() {
      let controls = Self.controls(
        .noCard, queued: Self.documents, signing: false, readingCard: true)
      #expect(controls.showsIdentity)
      #expect(controls.offersSigning)
      #expect(controls.actions == [.verify, .sign])
    }

    /// Sign stays held back until a failure in the status row is read.
    @Test
    internal func signWaitsUntilAFailureIsAcknowledged() {
      let failing = Self.controls(
        .ready, queued: Self.documents, signing: false, failureShown: true)
      let read = Self.controls(.ready, queued: Self.documents, signing: false)

      #expect(failing.awaitsAcknowledgement)
      #expect(!failing.allowsSigning(cardReady: true))
      #expect(read.allowsSigning(cardReady: true))
      #expect(!read.allowsSigning(cardReady: false))
    }
  }

#endif
