// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// PIN 1 held for one card, and every event that ends it (RAPP v26.10.29
/// §8.4 item 1, §11 item 2).
@Suite
internal struct CardBoundPin1Tests {
  /// A card as the holder of the value names it.
  private enum Card: Equatable {
    case first
    case second
  }

  private static let pinDigits = "1234"
  private static let otherPinDigits = "5678"

  private static func entry(_ digits: String) throws -> Pin1Entry {
    try #require(Pin1Entry(digits: digits))
  }

  private static func holding(
    _ pin1: Pin1Entry,
    for card: Card
  ) -> CardBoundPin1<Card> {
    var held = CardBoundPin1<Card>()
    held.hold(pin1, card: card)
    return held
  }

  @Test
  internal func startsEmpty() {
    var held = CardBoundPin1<Card>()
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func servesTheValueToItsCard() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    #expect(held.current(card: .first) === pin1)
    // Serving does not spend it.
    #expect(held.current(card: .first) === pin1)
  }

  @Test
  internal func anotherCardAskingForgetsIt() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    #expect(held.current(card: .second) == nil)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func noCardAskingForgetsIt() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    #expect(held.current(card: nil) == nil)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func theSameCardStayingKeepsIt() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    held.keep(onlyFor: .first)
    #expect(held.current(card: .first) === pin1)
  }

  @Test
  internal func anotherCardArrivingForgetsIt() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    held.keep(onlyFor: .second)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func theCardLeavingForgetsIt() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    held.keep(onlyFor: nil)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func clearingForgetsIt() throws {
    // The card refusing the value and the holder forgetting everything
    // both clear it.
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    held.clear()
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func aNewValueReplacesTheOldOne() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    var held = Self.holding(pin1, for: .first)
    let other = try Self.entry(Self.otherPinDigits)
    held.hold(other, card: .second)
    #expect(held.current(card: .second) === other)
    #expect(held.current(card: .first) == nil)
  }
}
