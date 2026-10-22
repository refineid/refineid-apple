// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import SwiftUI
  import Testing

  @testable import RefineID

  /// The words of a paired phone's line, and their colors.
  @Suite
  internal struct PairedPhoneLineTests {
    private static let phone = "Alpha iPhone"

    private static let holder = "SAMPLE HOLDER"

    /// The attribute the line's colors are set in.
    private static let color = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self

    /// The holder's name keeps the primary color; the phone's part after it
    /// takes the secondary one.
    @Test
    internal func pairedLineNamesThePhoneAfterTheHolder() throws {
      let line = PairedPhoneLine.line(lead: .holder, phone: Self.phone, holder: Self.holder)
      let suffix = " " + String(localized: "(paired phone: \(Self.phone))")
      #expect(String(line.characters) == Self.holder + suffix)
      let first = try #require(line.runs.first)
      let last = try #require(line.runs.last)
      #expect(String(line[first.range].characters) == Self.holder)
      #expect(first[Self.color] == nil)
      #expect(String(line[last.range].characters) == suffix)
      #expect(last[Self.color] == .secondary)
    }

    /// An instruction before the phone's part is secondary too.
    @Test
    internal func pairedLineAsksForThePhoneCardInTheSecondaryColor() {
      let line = PairedPhoneLine.line(
        lead: .phoneCard(.placeOnPhone), phone: Self.phone, holder: nil)
      let expected =
        PhoneCardRequestLine.instruction(for: .placeOnPhone) + " "
        + String(localized: "(paired phone: \(Self.phone))")
      #expect(String(line.characters) == expected)
      #expect(line.runs.allSatisfy { $0[Self.color] == .secondary })
    }

    /// With nothing before it, a phone out of sight, or a holder not yet
    /// read, the phone's part stands alone.
    @Test(arguments: [IdentityLine.PairedLead.away, .holder])
    internal func pairedLineNamesThePhoneAlone(_ lead: IdentityLine.PairedLead) {
      let line = PairedPhoneLine.line(lead: lead, phone: Self.phone, holder: nil)
      #expect(String(line.characters) == String(localized: "Paired phone: \(Self.phone)"))
      #expect(line.runs.allSatisfy { $0[Self.color] == .secondary })
    }
  }

#endif
