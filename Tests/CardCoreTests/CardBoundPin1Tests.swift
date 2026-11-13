// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// PIN 1 held for one card, and every event that ends it (RAPP v26.11.8
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
  private static let fiveRemaining: UInt8 = 5
  private static let fourRemaining: UInt8 = 4
  private static let threeRemaining: UInt8 = 3
  private static let twoRemaining: UInt8 = 2
  private static let oneRemaining: UInt8 = 1
  private static let zeroRemaining: UInt8 = 0
  private static let unknownStatus: UInt16 = 0x6F00

  private static func remaining(_ count: UInt8) throws -> RetryProbeOutcome {
    .remaining(try #require(RetryCount(attemptsRemaining: count)))
  }

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

  @Test
  internal func acceptedHoldFollowsPin1RetentionBeforeVerify() throws {
    let pin1 = try Self.entry(Self.pinDigits)
    for permitted in [try Self.remaining(Self.fiveRemaining), .verified] {
      var held = CardBoundPin1<Card>()
      held.settle(.accepted(pin1, preVerifyProbe: permitted, card: .first))
      #expect(held.current(card: .first) === pin1)
    }

    let forbidden: [RetryProbeOutcome] = [
      try Self.remaining(Self.fourRemaining),
      try Self.remaining(Self.threeRemaining),
      .noInformation,
      .other(Self.unknownStatus),
    ]
    for probe in forbidden {
      var held = Self.holding(try Self.entry(Self.otherPinDigits), for: .first)
      held.settle(.accepted(pin1, preVerifyProbe: probe, card: .first))
      #expect(held.current(card: .first) == nil)
    }

    var unnamed = Self.holding(try Self.entry(Self.otherPinDigits), for: .first)
    unnamed.settle(
      .accepted(pin1, preVerifyProbe: try Self.remaining(Self.fiveRemaining), card: nil))
    #expect(unnamed.current(card: .first) == nil)
  }

  @Test
  internal func nonPristineAndUnreadProbesClearAHeldValue() throws {
    let clearingProbes: [RetryProbeOutcome] = [
      try Self.remaining(Self.fourRemaining),
      try Self.remaining(Self.threeRemaining),
      try Self.remaining(Self.twoRemaining),
      try Self.remaining(Self.oneRemaining),
      try Self.remaining(Self.zeroRemaining),
      .locked,
      .invalidated,
      .noInformation,
      .other(Self.unknownStatus),
    ]
    for probe in clearingProbes {
      var held = Self.holding(try Self.entry(Self.pinDigits), for: .first)
      held.settle(.probed(probe))
      #expect(held.current(card: .first) == nil)
    }

    for permitted in [try Self.remaining(Self.fiveRemaining), .verified] {
      let pin1 = try Self.entry(Self.pinDigits)
      var held = Self.holding(pin1, for: .first)
      held.settle(.probed(permitted))
      #expect(held.current(card: .first) === pin1)
    }
  }

  @Test
  internal func cardUnavailableHoldsNothingNew() throws {
    var empty = CardBoundPin1<Card>()
    empty.settle(.cardUnavailable)
    #expect(empty.current(card: .first) == nil)

    let existing = try Self.entry(Self.pinDigits)
    var alreadyHolding = Self.holding(existing, for: .first)
    alreadyHolding.settle(.cardUnavailable)
    #expect(alreadyHolding.current(card: .first) === existing)

    alreadyHolding.settle(.clear)
    #expect(alreadyHolding.current(card: .first) == nil)
  }

  @Test
  internal func vaultClearsImmediatelyOnForbiddenProbeAndRejectsStaleEpochAccept() throws {
    let vault = CardBoundPin1<Card>.Vault()
    let initial = try Self.entry(Self.pinDigits)
    let replacement = try Self.entry(Self.otherPinDigits)
    vault.hold(initial, card: .first)

    // A non-pristine probe destroys custody at once before an operation finishes.
    #expect(!vault.retain(after: try Self.remaining(Self.fourRemaining)))
    #expect(vault.current(card: .first) == nil)

    // A forget or card removal while an operation is in flight advances the
    // epoch so a late accepted settlement cannot revive custody.
    vault.hold(initial, card: .first)
    let startingEpoch = vault.epoch
    vault.clear()
    vault.settle(
      .accepted(
        replacement,
        preVerifyProbe: try Self.remaining(Self.fiveRemaining),
        card: .first
      ),
      startingEpoch: startingEpoch
    )
    #expect(vault.current(card: .first) == nil)

    let cardRemovedEpoch = vault.epoch
    vault.keep(onlyFor: nil)
    vault.settle(
      .accepted(
        replacement,
        preVerifyProbe: try Self.remaining(Self.fiveRemaining),
        card: .first
      ),
      startingEpoch: cardRemovedEpoch
    )
    #expect(vault.current(card: .first) == nil)

    let liveEpoch = vault.epoch
    vault.settle(
      .accepted(
        replacement,
        preVerifyProbe: try Self.remaining(Self.fiveRemaining),
        card: .first
      ),
      startingEpoch: liveEpoch
    )
    #expect(vault.current(card: .first) === replacement)
  }
}
