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

  private static func holding(for card: Card) -> CardBoundPin1<Card> {
    var held = CardBoundPin1<Card>()
    held.hold(Self.pinDigits, card: card)
    return held
  }

  @Test
  internal func startsEmpty() {
    var held = CardBoundPin1<Card>()
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func servesTheValueToItsCard() {
    var held = Self.holding(for: .first)
    #expect(held.current(card: .first) == Self.pinDigits)
    // Serving does not spend it.
    #expect(held.current(card: .first) == Self.pinDigits)
  }

  @Test
  internal func anotherCardAskingForgetsIt() {
    var held = Self.holding(for: .first)
    #expect(held.current(card: .second) == nil)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func noCardAskingForgetsIt() {
    var held = Self.holding(for: .first)
    #expect(held.current(card: nil) == nil)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func theSameCardStayingKeepsIt() {
    var held = Self.holding(for: .first)
    held.keep(onlyFor: .first)
    #expect(held.current(card: .first) == Self.pinDigits)
  }

  @Test
  internal func anotherCardArrivingForgetsIt() {
    var held = Self.holding(for: .first)
    held.keep(onlyFor: .second)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func theCardLeavingForgetsIt() {
    var held = Self.holding(for: .first)
    held.keep(onlyFor: nil)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func clearingForgetsIt() {
    // The card refusing the value and the holder forgetting everything
    // both clear it.
    var held = Self.holding(for: .first)
    held.clear()
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func anEmptyValueForgetsIt() {
    var held = Self.holding(for: .first)
    held.hold("", card: .first)
    #expect(held.current(card: .first) == nil)
  }

  @Test
  internal func aNewValueReplacesTheOldOne() {
    var held = Self.holding(for: .first)
    held.hold(Self.otherPinDigits, card: .second)
    #expect(held.current(card: .second) == Self.otherPinDigits)
    #expect(held.current(card: .first) == nil)
  }
}
