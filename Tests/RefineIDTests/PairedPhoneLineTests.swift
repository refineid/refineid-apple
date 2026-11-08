// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import SwiftUI
  import Testing

  @testable import RefineIDTestHost

  /// The words of a paired phone's line, and their colors.
  @Suite
  internal struct PairedPhoneLineTests {
    private static let holder = "SAMPLE HOLDER"

    /// The attribute the line's colors are set in.
    private static let color = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self

    /// The holder's name keeps the primary color; "(via phone)" after it
    /// takes the secondary one.
    @Test
    internal func holderLineSaysViaPhoneAfterTheHolder() throws {
      let line = PairedPhoneLine.line(lead: .holder, holder: Self.holder)
      let suffix = " " + String(localized: "(via phone)")
      #expect(String(line.characters) == Self.holder + suffix)
      let first = try #require(line.runs.first)
      let last = try #require(line.runs.last)
      #expect(String(line[first.range].characters) == Self.holder)
      #expect(first[Self.color] == nil)
      #expect(String(line[last.range].characters) == suffix)
      #expect(last[Self.color] == .secondary)
    }

    /// The request for the phone's card reader is secondary throughout.
    @Test
    internal func phoneReaderLineAsksForTheCardAlone() {
      let line = PairedPhoneLine.line(lead: .phoneReader, holder: Self.holder)
      #expect(
        String(line.characters)
          == String(localized: "Insert the card into the phone's card reader."))
      #expect(line.runs.allSatisfy { $0[Self.color] == .secondary })
    }

    /// Until the holder's name is read, the line says nothing: no status
    /// names the phone (RAPP v26.11.8 §4.7).
    @Test(arguments: [nil, ""] as [String?])
    internal func holderLineWithoutANameIsEmpty(_ holder: String?) {
      let line = PairedPhoneLine.line(lead: .holder, holder: holder)
      #expect(String(line.characters).isEmpty)
    }
  }

#endif
