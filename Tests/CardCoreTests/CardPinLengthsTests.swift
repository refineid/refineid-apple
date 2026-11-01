// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The card's PIN lengths: EF.AOD mapped onto PIN 1, PIN 2 and the PUK
/// under the resolved numbering, clamped to what the role types carry,
/// and the FINEID bounds for whatever the card does not list.
@Suite
internal struct CardPinLengthsTests {
  /// A card-listed PIN 1 maximum below the stored length.
  private static let shortPin1Maximum = 8
  /// A card-listed PIN 2 minimum below the FINEID bound.
  private static let shortPin2Minimum = 4
  /// A card-listed range below what the PIN role types carry.
  private static let belowCapacityMinimum = 2
  private static let belowCapacityMaximum = 3
  /// A card-listed maximum above what the role types carry.
  private static let longMaximum = 16
  /// A reference no FINEID numbering uses.
  private static let unknownReference: UInt8 = 21

  private static func range(_ minimum: Int, _ maximum: Int) throws -> PasswordLengthRange {
    try #require(PasswordLengthRange(minimum: minimum, maximum: maximum))
  }

  private static func directory(_ objects: [AuthenticationObjectFixture]) throws
    -> AuthenticationObjectDirectory
  {
    try #require(
      AuthenticationObjectDirectory.parse(AuthenticationObjectFixture.file(objects.map(\.encoded))))
  }

  private static func object(
    _ reference: UInt8, _ minimum: Int, maximum: Int? = nil
  ) -> AuthenticationObjectFixture {
    var object = AuthenticationObjectFixture.citizen(reference: reference, minimum: minimum)
    object.maximum = maximum
    return object
  }

  @Test
  internal func aCardListingNothingTakesTheFineidBounds() throws {
    let lengths = CardPinLengths.mapping(nil, numbering: .citizen)
    #expect(lengths == .notListed(numbering: .citizen))
    #expect(lengths.pin1.listed == nil)
    #expect(
      lengths.pin1.accepted == (try Self.range(Pin1.minimumDigitCount, Pin1.maximumDigitCount)))
    #expect(
      lengths.pin2.accepted
        == (try Self.range(CardPinLengths.fineidPin2MinimumDigitCount, Pin2.maximumDigitCount)))
    #expect(lengths.puk.accepted == (try Self.range(Puk.minimumDigitCount, Puk.maximumDigitCount)))
  }

  @Test
  internal func citizenReferencesMapWithOrWithoutTheLocalBit() throws {
    let stored = Int(AuthenticationObjectFixture.storedLength)
    let directory = try Self.directory([
      Self.object(
        FineidValues.pin1Reference, Pin1.minimumDigitCount, maximum: Self.shortPin1Maximum),
      Self.object(
        FineidValues.pin2Reference & ~FineidValues.specificReferenceBit, Self.shortPin2Minimum),
      Self.object(FineidValues.pukReference, Puk.minimumDigitCount),
    ])
    let lengths = CardPinLengths.mapping(directory, numbering: .citizen)
    #expect(lengths.numbering == .citizen)
    #expect(
      lengths.pin1.accepted == (try Self.range(Pin1.minimumDigitCount, Self.shortPin1Maximum)))
    #expect(lengths.pin2.accepted == (try Self.range(Self.shortPin2Minimum, stored)))
    #expect(lengths.puk.accepted == (try Self.range(Puk.minimumDigitCount, stored)))
  }

  @Test
  internal func organizationReferencesMapUnderTheirNumbering() throws {
    let directory = try Self.directory([
      Self.object(FineidValues.organizationPin1Reference, Pin1.minimumDigitCount),
      Self.object(
        FineidValues.pin1Reference, Self.shortPin2Minimum, maximum: Self.shortPin1Maximum),
    ])
    let lengths = CardPinLengths.mapping(directory, numbering: .organization)
    #expect(lengths.numbering == .organization)
    #expect(lengths.pin1.listed == (try Self.range(Pin1.minimumDigitCount, Pin1.maximumDigitCount)))
    #expect(lengths.pin2.listed == nil)
    #expect(lengths.puk.listed == nil)
  }

  @Test
  internal func unknownAndRepeatedReferencesAreNotListed() throws {
    let directory = try Self.directory([
      Self.object(Self.unknownReference, Self.shortPin2Minimum),
      Self.object(FineidValues.pin2Reference, Self.shortPin2Minimum),
      Self.object(FineidValues.pin2Reference, Pin1.minimumDigitCount),
    ])
    let lengths = CardPinLengths.mapping(directory, numbering: .citizen)
    #expect(lengths == .notListed(numbering: .citizen))
  }

  @Test
  internal func aListedRangeIsClampedToWhatTheTypeCarries() throws {
    let directory = try Self.directory([
      Self.object(FineidValues.pin1Reference, Pin1.minimumDigitCount, maximum: Self.longMaximum),
      Self.object(
        FineidValues.pin2Reference, Self.belowCapacityMinimum, maximum: Self.belowCapacityMaximum),
    ])
    let lengths = CardPinLengths.mapping(directory, numbering: .citizen)
    #expect(
      lengths.pin1.accepted == (try Self.range(Pin1.minimumDigitCount, Pin1.maximumDigitCount)))
    #expect(lengths.pin2.listed != nil)
    #expect(lengths.pin2.accepted == nil)
    #expect(!lengths.pin2.accepts(digitCount: Self.belowCapacityMaximum))
    #expect(!lengths.pin2.accepts(digitCount: Pin2.minimumDigitCount))
  }

  @Test
  internal func pin2CarriesFourDigits() {
    let shortest = String(repeating: "7", count: Self.shortPin2Minimum)
    #expect(Pin2.minimumDigitCount == Self.shortPin2Minimum)
    let constructed: Bool =
      switch Pin2(digits: shortest) {
      case .some:
        true

      case .none:
        false
      }
    #expect(constructed)
  }

  @Test
  internal func readsTheDirectoryUnderThePkcs15Application() throws {
    let file = AuthenticationObjectFixture.file([
      Self.object(
        FineidValues.pin1Reference, Pin1.minimumDigitCount, maximum: Self.shortPin1Maximum
      )
      .encoded
    ])
    let operations = CardOperations(channel: DirectoryServingCard(directory: file))
    let lengths = try operations.readCardPinLengths()
    #expect(
      lengths.pin1.accepted == (try Self.range(Pin1.minimumDigitCount, Self.shortPin1Maximum)))
    #expect(lengths.pin2 == CardPinLengths.notListed(numbering: .citizen).pin2)
  }

  @Test
  internal func anAbsentDirectoryListsNothing() throws {
    let operations = CardOperations(channel: DirectoryServingCard(directory: nil))
    #expect(try operations.readCardPinLengths() == .notListed(numbering: .citizen))
  }

  @Test
  internal func anUndecodableDirectoryListsNothing() throws {
    let undecodable = Data(Pkcs15Values.passwordTypeUtf8.description.utf8)
    let operations = CardOperations(channel: DirectoryServingCard(directory: undecodable))
    #expect(try operations.readCardPinLengths() == .notListed(numbering: .citizen))
  }
}
