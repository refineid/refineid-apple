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

    /// The holder's name keeps the primary color; the phone's label after
    /// it takes the secondary one.
    @Test
    internal func holderLineNamesThePhoneAfterTheHolder() throws {
      let line = PairedPhoneLine.line(lead: .holder, phone: Self.phone, holder: Self.holder)
      let suffix = " " + String(localized: "(paired: \(Self.phone))")
      #expect(String(line.characters) == Self.holder + suffix)
      let first = try #require(line.runs.first)
      let last = try #require(line.runs.last)
      #expect(String(line[first.range].characters) == Self.holder)
      #expect(first[Self.color] == nil)
      #expect(String(line[last.range].characters) == suffix)
      #expect(last[Self.color] == .secondary)
    }

    /// Connecting, the line names no phone and is secondary throughout.
    @Test
    internal func connectingLineNamesNoPhone() {
      let line = PairedPhoneLine.line(lead: .connecting, phone: Self.phone, holder: Self.holder)
      #expect(String(line.characters) == String(localized: "Connecting to the phone…"))
      #expect(line.runs.allSatisfy { $0[Self.color] == .secondary })
    }

    /// The request for the phone's card reader names no phone and is
    /// secondary throughout.
    @Test
    internal func phoneReaderLineAsksForTheCardAlone() {
      let line = PairedPhoneLine.line(lead: .phoneReader, phone: Self.phone, holder: Self.holder)
      #expect(
        String(line.characters)
          == String(localized: "Insert the card into the phone's card reader."))
      #expect(line.runs.allSatisfy { $0[Self.color] == .secondary })
    }

    /// Until the holder's name is read, the holder's line says it is
    /// connecting.
    @Test(arguments: [nil, ""] as [String?])
    internal func holderLineWithoutANameIsConnecting(_ holder: String?) {
      let line = PairedPhoneLine.line(lead: .holder, phone: Self.phone, holder: holder)
      #expect(String(line.characters) == String(localized: "Connecting to the phone…"))
      #expect(line.runs.allSatisfy { $0[Self.color] == .secondary })
    }
  }

#endif
