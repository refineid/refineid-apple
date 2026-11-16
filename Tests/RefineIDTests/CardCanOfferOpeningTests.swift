// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore
@testable import RefineIDTestHost

/// The card access number an app-side operation opens a contactless
/// citizen card with, and the pre-PACE status-word classification.
@Suite(.serialized)
internal struct CardCanOfferOpeningTests {
  #if FEATURE_CONTACTLESS
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

    #if os(macOS)
      @Test
      internal func aNumberOnlyInTheDriversLibraryOpensTheCard() {
        Self.cleanupOpening()
        defer { Self.cleanupOpening() }
        CardCanOffer.remember(digits: Self.libraryDigits, printedSerial: Self.printedSerial)

        #expect(CardMaintenance.offeredAccessNumber(nil)?.digits == Self.libraryDigits)
      }
    #else
      @Test
      internal func aStoredNumberOpensTheCardOnIOS() {
        Self.cleanupOpening()
        defer { Self.cleanupOpening() }
        #expect(CardCredentialStore.save(cardAccessNumber: Self.libraryDigits) == errSecSuccess)

        #expect(
          CardMaintenance.offeredAccessNumber(nil)?.number.derivedPasswordKey()
            == CardAccessNumber(digits: Self.libraryDigits)?.derivedPasswordKey())
      }
    #endif

    @Test
    internal func theOperationsOwnNumberComesFirst() {
      Self.cleanupOpening()
      defer { Self.cleanupOpening() }
      CardCanOffer.remember(digits: Self.libraryDigits, printedSerial: Self.printedSerial)
      #expect(CardCredentialStore.save(cardAccessNumber: Self.libraryDigits) == errSecSuccess)

      #expect(
        CardMaintenance.offeredAccessNumber(Self.offeredDigits)?.digits == Self.offeredDigits)
    }
  #endif

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
