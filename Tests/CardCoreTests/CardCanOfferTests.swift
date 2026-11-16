// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

/// The keychain card-number handoff: one active offer plus a
/// per-card library, machine use only.
@Suite(.serialized)
internal struct CardCanOfferTests {
  /// Clears the offer, the library entries a test named, and the
  /// stored number.
  private static func cleanup(serials: [String] = []) {
    CardCanOffer.withdraw()
    #if !os(macOS)
      for serial in serials {
        CardCanOffer.forget(printedSerial: serial)
      }
    #endif
    CardCredentialStore.delete(account: CardCredentialStore.cardAccessNumberAccount)
  }

  @Test
  internal func offerRoundTrip() {
    Self.cleanup()
    defer { Self.cleanup() }
    #expect(CardCanOffer.offeredDigits() == nil)
    #expect(CardCanOffer.publish(digits: "123677"))
    #expect(CardCanOffer.offeredDigits() == "123677")
    CardCanOffer.withdraw()
    #expect(CardCanOffer.offeredDigits() == nil)
  }

  @Test
  internal func invalidOfferIsRefused() {
    Self.cleanup()
    defer { Self.cleanup() }
    #expect(!CardCanOffer.publish(digits: "12345"))
    #expect(CardCanOffer.offeredDigits() == nil)
  }

  #if !os(macOS)
    @Test
    internal func libraryAccountNamesThePrintedSerial() {
      #expect(
        CardCanOffer.libraryAccount(printedSerial: "HA2167943")
          == "refineid-card-ha2167943-can")
    }
  #endif

  #if !os(macOS)
    /// iOS tries the one stored number: the offer and the library are
    /// macOS-handoff state the iOS branch ignores.
    @Test
    internal func candidatesHoldOnlyTheStoredNumber() {
      Self.cleanup(serials: ["AA0000001", "BB0000002"])
      defer { Self.cleanup(serials: ["AA0000001", "BB0000002"]) }
      #expect(CardCredentialStore.save(cardAccessNumber: "111111") == errSecSuccess)
      #expect(CardCanOffer.publish(digits: "222222"))
      CardCanOffer.remember(digits: "222222", printedSerial: "AA0000001")
      CardCanOffer.remember(digits: "333333", printedSerial: "BB0000002")

      let candidates = CardCredentialStore.cardAccessNumberCandidates()
      #expect(candidates.count == 1)
      #expect(
        candidates.first?.number.derivedPasswordKey()
          == CardAccessNumber(digits: "111111")?.derivedPasswordKey())
    }
  #endif

  #if !os(macOS)
    /// Without a stored number there is nothing to try: the offer and
    /// the library alone open no card.
    @Test
    internal func candidatesAreEmptyWithoutAStoredNumber() {
      Self.cleanup(serials: ["BD0000001"])
      defer { Self.cleanup(serials: ["BD0000001"]) }
      #expect(CardCanOffer.publish(digits: "222222"))
      CardCanOffer.remember(digits: "333333", printedSerial: "BD0000001")

      #expect(CardCredentialStore.cardAccessNumberCandidates().isEmpty)
    }
  #endif

  #if !os(macOS)
    /// Forgetting wipes the stored number but keeps the refusal marker,
    /// the offer, and the library: those are handoff state, not stored
    /// numbers.
    @Test
    internal func refusalWipesTheStoredNumberButKeepsMarkerOfferAndLibrary() {
      Self.cleanup(serials: ["AA0000001", "BB0000002"])
      defer { Self.cleanup(serials: ["AA0000001", "BB0000002"]) }
      #expect(CardCredentialStore.save(cardAccessNumber: "111111") == errSecSuccess)
      #expect(CardCanOffer.publish(digits: "222222"))
      CardCanOffer.remember(digits: "222222", printedSerial: "AA0000001")
      CardCanOffer.remember(digits: "333333", printedSerial: "BB0000002")
      CardCanOffer.recordRefusal()

      CardCredentialStore.forgetEveryCardAccessNumber()

      #expect(!CardCredentialStore.hasStoredNumbers())
      #expect(CardCanOffer.refusalRecorded())
      #expect(CardCanOffer.offeredDigits() == "222222")
      #expect(CardCanOffer.storedSerials().count == 2)
    }
  #endif

  #if !os(macOS)
    @Test
    internal func refusalMarkerRoundTrip() {
      Self.cleanup()
      defer { Self.cleanup() }
      #expect(!CardCanOffer.refusalRecorded())
      CardCanOffer.recordRefusal()
      #expect(CardCanOffer.refusalRecorded())
      CardCanOffer.clearRefusal()
      #expect(!CardCanOffer.refusalRecorded())
    }
  #endif

  #if !os(macOS)
    @Test
    internal func publishClearsAStandingRefusal() {
      Self.cleanup()
      defer { Self.cleanup() }
      CardCanOffer.recordRefusal()
      #expect(CardCanOffer.publish(digits: "123677"))
      #expect(!CardCanOffer.refusalRecorded())
    }
  #endif

  @Test
  internal func accessGroupIsOnlySetWhenShared() {
    let ungrouped = CardCredentialStore.query(account: "refineid-offer-can", accessGroup: nil)
    #expect(ungrouped[kSecAttrAccessGroup as String] == nil)
    #expect(
      ungrouped[kSecUseDataProtectionKeychain as String] as? Bool
        == KeychainPlatform.usesDataProtection)
    let grouped = CardCredentialStore.query(
      account: "refineid-offer-can", accessGroup: "GRP.fi.refineid.ReFineID")
    #expect(
      grouped[kSecAttrAccessGroup as String] as? String == "GRP.fi.refineid.ReFineID")
    #expect(grouped[kSecUseDataProtectionKeychain as String] as? Bool == true)
  }

  #if !os(macOS)
    @Test
    internal func libraryListsOnlyLibraryAccounts() {
      Self.cleanup(serials: ["CC0000001"])
      defer { Self.cleanup(serials: ["CC0000001"]) }
      #expect(CardCanOffer.publish(digits: "123677"))
      CardCanOffer.remember(digits: "444444", printedSerial: "CC0000001")

      #expect(
        CardCanOffer.libraryAccounts() == [
          CardCanOffer.libraryAccount(printedSerial: "CC0000001")
        ])
    }
  #endif
}
