// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// Setup binds the credential to Settings before any card I/O.
  internal struct CardSetupEntryTests {
    private static let decimalDigits = Array("0123456789")

    private static func digits(count: Int) -> String {
      String(
        String(repeating: "x", count: count).map { _ in
          Self.decimalDigits.randomElement() ?? "0"
        })
    }

    @Test
    internal func personalEntryCannotBecomePin1() throws {
      let accepted = CardPriming.SetupEntry(
        digits: Self.digits(count: CardAccessNumber.digitCount), kind: .personal)
      let entry = try #require(accepted)
      #expect(entry.kind == .personal)
      #expect(entry.personalAccessNumber() != nil)
      #expect(entry.organizationPin1() == nil)
      #expect(Mirror(reflecting: entry).children.isEmpty)
    }

    @Test
    internal func organizationEntryCannotBecomeCan() throws {
      let accepted = CardPriming.SetupEntry(
        digits: Self.digits(count: CardAccessNumber.digitCount), kind: .organization)
      let entry = try #require(accepted)
      #expect(entry.kind == .organization)
      #expect(entry.personalAccessNumber() == nil)
      #expect(entry.organizationPin1() != nil)
      #expect(Mirror(reflecting: entry).children.isEmpty)
    }

    @Test
    internal func personalModeRejectsOrganizationOnlyEntries() {
      for count in [Pin1.minimumDigitCount, Pin1.maximumDigitCount] {
        let accepted = CardPriming.SetupEntry(digits: Self.digits(count: count), kind: .personal)
        #expect(accepted == nil)
      }
    }

    @Test
    internal func organizationModeAcceptsItsCredentialBounds() {
      for count in [Pin1.minimumDigitCount, Pin1.maximumDigitCount] {
        let accepted = CardPriming.SetupEntry(
          digits: Self.digits(count: count), kind: .organization)
        #expect(accepted != nil)
      }
    }

    @Test(arguments: [ContactlessCardKind.personal, .organization])
    internal func invalidEntryIsRefused(kind: ContactlessCardKind) {
      let accepted = CardPriming.SetupEntry(digits: "not a credential", kind: kind)
      #expect(accepted == nil)
    }
  }
#endif
