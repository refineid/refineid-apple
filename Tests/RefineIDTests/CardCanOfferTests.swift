// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// The keychain card-number handoff: one active offer plus a
  /// per-card library, machine use only.
  @Suite(.serialized)
  internal struct CardCanOfferTests {
    private static func cleanup(serials: [String] = []) {
      CardCanOffer.withdraw()
      for serial in serials {
        CardCanOffer.forget(printedSerial: serial)
      }
      CardCredentialStore.delete(account: CardCredentialStore.cardAccessNumberAccount)
    }

    @Test
    internal func offerRoundTrip() {
      defer { Self.cleanup() }
      #expect(CardCanOffer.offeredDigits() == nil)
      #expect(CardCanOffer.publish(digits: "123677"))
      #expect(CardCanOffer.offeredDigits() == "123677")
      CardCanOffer.withdraw()
      #expect(CardCanOffer.offeredDigits() == nil)
    }

    @Test
    internal func invalidOfferIsRefused() {
      defer { Self.cleanup() }
      #expect(!CardCanOffer.publish(digits: "12345"))
      #expect(CardCanOffer.offeredDigits() == nil)
    }

    @Test
    internal func libraryAccountNamesThePrintedSerial() {
      #expect(
        CardCanOffer.libraryAccount(printedSerial: "HA2167943")
          == "refineid-card-ha2167943-can")
    }

    @Test
    internal func candidatesPreferOfferThenLibraryDeduplicated() {
      defer { Self.cleanup(serials: ["AA0000001", "BB0000002"]) }
      #expect(CardCredentialStore.save(cardAccessNumber: "111111") == errSecSuccess)
      #expect(CardCanOffer.publish(digits: "222222"))
      CardCanOffer.remember(digits: "222222", printedSerial: "AA0000001")
      CardCanOffer.remember(digits: "333333", printedSerial: "BB0000002")

      let digits = CardCredentialStore.cardAccessNumberCandidates().map(\.digits)
      #expect(digits == ["111111", "222222", "333333"])
    }

    @Test
    internal func candidatesAreBounded() {
      let serials = (1...6).map { "BD000000\($0)" }
      defer { Self.cleanup(serials: serials) }
      for (index, serial) in serials.enumerated() {
        CardCanOffer.remember(digits: "10000\(index)", printedSerial: serial)
      }

      let digits = CardCredentialStore.cardAccessNumberCandidates().map(\.digits)
      #expect(digits.count == CardCanOffer.maximumCandidates)
    }

    @Test
    internal func refusalMarkerRoundTrip() {
      defer { Self.cleanup() }
      #expect(!CardCanOffer.refusalRecorded())
      CardCanOffer.recordRefusal()
      #expect(CardCanOffer.refusalRecorded())
      CardCanOffer.clearRefusal()
      #expect(!CardCanOffer.refusalRecorded())
    }

    @Test
    internal func publishClearsAStandingRefusal() {
      defer { Self.cleanup() }
      CardCanOffer.recordRefusal()
      #expect(CardCanOffer.publish(digits: "123677"))
      #expect(!CardCanOffer.refusalRecorded())
    }

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

    @Test
    internal func libraryListsOnlyLibraryAccounts() {
      defer { Self.cleanup(serials: ["CC0000001"]) }
      #expect(CardCanOffer.publish(digits: "123677"))
      CardCanOffer.remember(digits: "444444", printedSerial: "CC0000001")

      #expect(
        CardCanOffer.libraryAccounts() == [
          CardCanOffer.libraryAccount(printedSerial: "CC0000001")
        ])
    }
  }

#endif
