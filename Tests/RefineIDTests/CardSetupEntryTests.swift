// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// The setup entry "Card Access Number (CAN)": four to twelve digits that
  /// become a personal card's access number or an organization card's
  /// PIN 1 only once the card has named its kind.
  internal struct CardSetupEntryTests {
    /// A fictitious entry of a personal card's length.
    private static let sixDigits = "246813"

    /// A fictitious entry of an organization card's shortest PIN 1.
    private static let fourDigits = "2468"

    /// A fictitious entry of an organization card's longest PIN 1.
    private static let twelveDigits = "246813579135"

    /// One digit beyond the longest PIN 1.
    private static let thirteenDigits = twelveDigits + "7"

    @Test(arguments: [fourDigits, sixDigits, twelveDigits])
    internal func fourToTwelveDigitsAreAnEntry(digits: String) {
      #expect(CardPriming.SetupEntry(digits: digits) != nil)
    }

    @Test(arguments: ["246", thirteenDigits, "24681a"])
    internal func anythingElseIsNoEntry(digits: String) {
      #expect(CardPriming.SetupEntry(digits: digits) == nil)
    }

    @Test
    internal func onlySixDigitsBecomeAPersonalCardsAccessNumber() throws {
      let six = try #require(CardPriming.SetupEntry(digits: Self.sixDigits))
      #expect(six.personalAccessNumber()?.digits == Self.sixDigits)
      let four = try #require(CardPriming.SetupEntry(digits: Self.fourDigits))
      #expect(four.personalAccessNumber() == nil)
      let twelve = try #require(CardPriming.SetupEntry(digits: Self.twelveDigits))
      #expect(twelve.personalAccessNumber() == nil)
    }

    @Test(arguments: [fourDigits, sixDigits, twelveDigits])
    internal func everyEntryBecomesAnOrganizationCardsPin1(digits: String) throws {
      let entry = try #require(CardPriming.SetupEntry(digits: digits))
      #expect(entry.organizationPin1() != nil)
    }

    @Test
    internal func theEntryReflectsNothing() throws {
      let entry = try #require(CardPriming.SetupEntry(digits: Self.sixDigits))
      #expect(Mirror(reflecting: entry).children.isEmpty)
      #expect(!((entry as Any) is CustomStringConvertible))
      #expect(!((entry as Any) is CardAccessNumber))
    }
  }

#endif
