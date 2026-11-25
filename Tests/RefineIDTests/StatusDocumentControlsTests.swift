// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import RappRequester
  import Testing

  @testable import RefineIDTestHost

  /// Which document controls the Mac window shows with and without a
  /// card or phone that can sign.
  @Suite
  internal struct StatusDocumentControlsTests {
    private static let documents = [URL(filePath: "/documents/contract.pdf")]

    /// The controls for one window state.
    private static func controls(
      _ availability: IdentityAvailability,
      queued: [URL],
      signing working: Bool,
      readingCard: Bool = false,
      failureShown: Bool = false,
      offersVerification: Bool = true
    ) -> StatusDocumentControls {
      StatusDocumentControls(
        availability: availability, queued: queued, signing: working,
        readingCard: readingCard, failureShown: failureShown,
        offersVerification: offersVerification, signingAvailable: true)
    }

    /// The default verification gate matches this build's compile flag.
    @Test
    internal func defaultOffersVerificationMatchesBuildFlag() {
      let controls = StatusDocumentControls(
        availability: .ready, queued: Self.documents, signing: false,
        readingCard: false, failureShown: false,
        offersVerification: StatusDocumentControls.defaultOffersVerification,
        signingAvailable: true)
      #if FEATURE_DOCUMENT_VERIFICATION
        #expect(StatusDocumentControls.defaultOffersVerification)
        #expect(controls.offersVerification)
        #expect(controls.actions == [.verify, .sign])
      #else
        #expect(!StatusDocumentControls.defaultOffersVerification)
        #expect(!controls.offersVerification)
        #expect(controls.actions == [.sign])
      #endif
    }

    /// With verification gated off, an absent card hides the empty drop
    /// area, keeps the reader prompt even when documents wait, and never
    /// offers Verify.
    @Test
    internal func withoutVerificationOnlySigningControlsAppear() {
      let emptyNoCard = Self.controls(
        .noCard, queued: [], signing: false, offersVerification: false)
      #expect(emptyNoCard.showsIdentity)
      #expect(!emptyNoCard.showsDocuments)
      #expect(!emptyNoCard.offersSigning)
      #expect(!emptyNoCard.verifyEnabled)
      #expect(emptyNoCard.actions.isEmpty)

      let queuedNoCard = Self.controls(
        .noCard, queued: Self.documents, signing: false, offersVerification: false)
      #expect(queuedNoCard.showsIdentity)
      #expect(queuedNoCard.showsDocuments)
      #expect(!queuedNoCard.offersSigning)
      #expect(!queuedNoCard.verifyEnabled)
      #expect(queuedNoCard.actions.isEmpty)

      let emptyReady = Self.controls(
        .ready, queued: [], signing: false, offersVerification: false)
      #expect(emptyReady.showsIdentity)
      #expect(emptyReady.showsDocuments)
      #expect(emptyReady.offersSigning)
      #expect(!emptyReady.verifyEnabled)
      #expect(emptyReady.actions.isEmpty)

      let queuedReady = Self.controls(
        .ready, queued: Self.documents, signing: false, offersVerification: false)
      #expect(queuedReady.showsIdentity)
      #expect(queuedReady.showsDocuments)
      #expect(queuedReady.offersSigning)
      #expect(!queuedReady.verifyEnabled)
      #expect(queuedReady.actions == [.sign])

      let inFlight = Self.controls(
        .noCard, queued: Self.documents, signing: true, offersVerification: false)
      #expect(inFlight.showsIdentity)
      #expect(inFlight.showsDocuments)
      #expect(inFlight.offersSigning)
      #expect(!inFlight.verifyEnabled)
      #expect(inFlight.actions == [.sign])
    }

    /// No card, nothing listed, verification on: the identity row still
    /// asks for a reader above the drop area, nothing about signing
    /// shows, and Verify cannot run yet.
    @Test
    internal func withoutACardAndNothingListedOnlyTheReaderRowAndDropArea() {
      let controls = Self.controls(.noCard, queued: [], signing: false)
      #expect(controls.showsIdentity)
      #expect(controls.showsDocuments)
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
      for availability in [IdentityAvailability.ready, .cardWithoutIdentity] {
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

    /// A visible refusal permits an explicit retry with a ready card.
    @Test
    internal func signCanRetryWhileAFailureIsVisible() {
      let failing = Self.controls(
        .ready, queued: Self.documents, signing: false, failureShown: true)
      let read = Self.controls(.ready, queued: Self.documents, signing: false)

      #expect(failing.failureIsVisible)
      #expect(failing.allowsSigning(cardReady: true))
      #expect(read.allowsSigning(cardReady: true))
      #expect(!read.allowsSigning(cardReady: false))
    }

    /// When signing is unavailable (for example EstEID 2025 initial PIN 2
    /// awaiting change), signing controls and the signing-only drop area stay
    /// hidden while verification stays available when compiled in.
    @Test
    internal func signingUnavailableBlocksSigningAndHidesSigningDropArea() {
      let signOnly = StatusDocumentControls(
        availability: .ready, queued: [], signing: false, readingCard: false,
        failureShown: false, offersVerification: false, signingAvailable: false
      )
      #expect(signOnly.showsIdentity)
      #expect(!signOnly.showsDocuments)
      #expect(!signOnly.offersSigning)
      #expect(!signOnly.allowsSigning(cardReady: true))
      #expect(signOnly.actions.isEmpty)

      let verifyAndSign = StatusDocumentControls(
        availability: .ready, queued: Self.documents, signing: false, readingCard: false,
        failureShown: false, offersVerification: true, signingAvailable: false
      )
      #expect(!verifyAndSign.offersSigning)
      #expect(!verifyAndSign.allowsSigning(cardReady: true))
      #expect(verifyAndSign.verifyEnabled)
      #expect(verifyAndSign.actions == [.verify])
    }
  }

#endif
