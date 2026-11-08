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

    /// No card, nothing listed: the identity row still asks for a
    /// reader above the drop area, nothing about signing shows, and
    /// Verify is there but cannot run.
    @Test
    internal func withoutACardAndNothingListedOnlyTheReaderRowAndDropArea() {
      let controls = StatusDocumentControls(availability: .noCard, queued: [], signing: false)
      #expect(controls.showsIdentity)
      #expect(!controls.offersSigning)
      #expect(!controls.verifyEnabled)
    }

    /// No card, documents listed: the reader row steps aside, nothing
    /// about signing shows, and Verify runs.
    @Test
    internal func withoutACardListedDocumentsAreForVerifyingOnly() {
      let controls = StatusDocumentControls(
        availability: .noCard, queued: Self.documents, signing: false)
      #expect(!controls.showsIdentity)
      #expect(!controls.offersSigning)
      #expect(controls.verifyEnabled)
    }

    /// A card or a paired phone's identity offers the identity row,
    /// the signing panel and Verify together.
    @Test
    internal func withACardSigningAndVerifyingAreBothOffered() {
      for availability in [LoginIdentityModel.Availability.ready, .cardWithoutIdentity] {
        let controls = StatusDocumentControls(
          availability: availability, queued: Self.documents, signing: false)
        #expect(controls.showsIdentity)
        #expect(controls.offersSigning)
        #expect(controls.verifyEnabled)
      }
      let empty = StatusDocumentControls(availability: .ready, queued: [], signing: false)
      #expect(empty.showsIdentity)
      #expect(empty.offersSigning)
      #expect(!empty.verifyEnabled)
    }

    /// While a signature runs Verify waits, and the signing panel stays
    /// even if the card's publication drops for a moment.
    @Test
    internal func whileSigningVerifyWaitsAndThePanelStays() {
      let controls = StatusDocumentControls(
        availability: .noCard, queued: Self.documents, signing: true)
      #expect(controls.showsIdentity)
      #expect(controls.offersSigning)
      #expect(!controls.verifyEnabled)
    }
  }

#endif
