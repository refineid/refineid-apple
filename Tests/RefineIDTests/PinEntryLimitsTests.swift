// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Testing

  @testable import RefineIDTestHost

  /// A credential field takes the card's lengths: digits only, kept to
  /// the card's longest value, complete from its shortest.
  @Suite
  internal struct PinEntryLimitsTests {
    private static let lengths = CardPinLengths.notListed(numbering: .citizen)

    private static func digits(_ count: Int) -> String {
      String(repeating: "7", count: count)
    }

    @Test
    internal func aPin2FieldStartsAtTheCardsShortest() throws {
      let limits = PinEntryLimits(Self.lengths, role: .pin2)
      let accepted = try #require(Self.lengths.pin2.accepted)
      #expect(!limits.accepts(Self.digits(accepted.minimum - 1)))
      #expect(limits.accepts(Self.digits(accepted.minimum)))
      #expect(limits.accepts(Self.digits(accepted.maximum)))
    }

    @Test
    internal func typingStopsAtTheCardsLongest() throws {
      let limits = PinEntryLimits(Self.lengths, role: .puk)
      let accepted = try #require(Self.lengths.puk.accepted)
      #expect(limits.limited(Self.digits(accepted.maximum + 1)) == Self.digits(accepted.maximum))
      #expect(limits.limited("12a3") == "123")
    }
  }

#endif
