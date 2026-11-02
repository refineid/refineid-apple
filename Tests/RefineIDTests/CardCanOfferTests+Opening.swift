// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// The card access number the window opens a citizen card on a reader's
  /// antenna with, for a signature that spends PIN 2.
  ///
  /// The token driver keeps the number a card opened with in the per-card
  /// library; the window's own signing must reach the same number, or a
  /// citizen card the login just opened is "not found" for a document.
  /// These run in the offer suite, which owns the shared keychain slots
  /// and runs its tests one at a time.
  extension CardCanOfferTests {
    /// A fictitious card access number.
    private static let libraryDigits = "246813"

    /// A fictitious number the operation offers itself.
    private static let offeredDigits = "135792"

    /// A fictitious printed serial for the library entry.
    private static let printedSerial = "ZZ0000009"

    private static func cleanupOpening() {
      CardCanOffer.withdraw()
      CardCanOffer.forget(printedSerial: printedSerial)
      CardCredentialStore.delete(account: CardCredentialStore.cardAccessNumberAccount)
    }

    @Test
    internal func aNumberOnlyInTheDriversLibraryOpensTheCard() {
      Self.cleanupOpening()
      defer { Self.cleanupOpening() }
      CardCanOffer.remember(digits: Self.libraryDigits, printedSerial: Self.printedSerial)

      #expect(CardMaintenance.offeredAccessNumber(nil)?.digits == Self.libraryDigits)
    }

    @Test
    internal func theOperationsOwnNumberComesFirst() {
      Self.cleanupOpening()
      defer { Self.cleanupOpening() }
      CardCanOffer.remember(digits: Self.libraryDigits, printedSerial: Self.printedSerial)

      #expect(
        CardMaintenance.offeredAccessNumber(Self.offeredDigits)?.digits == Self.offeredDigits)
    }

    @Test
    internal func aCitizenRefusalBeforePaceIsNotAnOrganizationCard() {
      // A citizen card on an antenna refuses the application with 6982,
      // which opens with the card access number; only 6985 takes a PIN.
      #expect(
        !CardOperationError.refusesBeforePace(
          CardOperationError.selectRejected(.securityNotSatisfied)))
      #expect(
        CardOperationError.refusesBeforePace(
          CardOperationError.selectRejected(.conditionsNotSatisfied)))
    }
  }

#endif
