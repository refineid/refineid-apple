// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// When the setup authentication prompt starts its NFC hold by itself:
  /// a personal card's six digits complete it, while an organization
  /// card's PIN 1 only completes at its longest length.
  internal struct SetupAuthenticationFlowTests {
    /// A fictitious entry of a personal card's length.
    private static let sixDigits = "246813"

    /// A fictitious entry of an organization card's shortest PIN 1.
    private static let fourDigits = "2468"

    /// A fictitious entry one digit short of the longest PIN 1.
    private static let elevenDigits = "24681357913"

    /// A fictitious entry of an organization card's longest PIN 1.
    private static let twelveDigits = "246813579135"

    /// One digit beyond the longest PIN 1.
    private static let thirteenDigits = twelveDigits + "7"

    @Test
    internal func sixthDigitStartsPersonalHold() {
      #expect(
        SetupAuthenticationFlow.shouldBeginHold(
          entry: Self.sixDigits,
          organizationMode: false
        )
      )
    }

    @Test(arguments: ["", "2", "24681", Self.twelveDigits, Self.thirteenDigits])
    internal func anythingElseWaitsForTheButtonInPersonalMode(digits: String) {
      #expect(
        !SetupAuthenticationFlow.shouldBeginHold(
          entry: digits,
          organizationMode: false
        )
      )
    }

    @Test(arguments: ["24681a", "abcdef"])
    internal func nonDigitsNeverStartAPersonalHold(digits: String) {
      #expect(
        !SetupAuthenticationFlow.shouldBeginHold(
          entry: digits,
          organizationMode: false
        )
      )
    }

    @Test
    internal func twelfthDigitStartsOrganizationHold() {
      #expect(
        SetupAuthenticationFlow.shouldBeginHold(
          entry: Self.twelveDigits,
          organizationMode: true
        )
      )
    }

    @Test(arguments: [fourDigits, sixDigits, elevenDigits])
    internal func shorterPinWaitsForTheButtonInOrganizationMode(digits: String) {
      #expect(
        !SetupAuthenticationFlow.shouldBeginHold(
          entry: digits,
          organizationMode: true
        )
      )
    }

    @Test(arguments: [thirteenDigits, "24681357913a"])
    internal func overlongEntryNeverStartsAnOrganizationHold(digits: String) {
      #expect(
        !SetupAuthenticationFlow.shouldBeginHold(
          entry: digits,
          organizationMode: true
        )
      )
    }
  }

#endif
