// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The token extension's one PIN 1 store: per chip serial, one value that
/// is either a typed candidate or a PIN the card accepted (RAPP v26.10.29
/// section 11 item 2).
@Suite
internal struct Pin1MemoryTests {
  private static let digits = "1234"
  private static let otherDigits = "654321"
  /// How many requests reuse one accepted PIN in a row.
  private static let reuses = 3

  private static func serial(_ value: String) -> ChipSerial {
    guard let serial = ChipSerial(value: value) else {
      fatalError("test serial must be valid")
    }
    return serial
  }

  private static func pin(_ digits: String) -> Pin1 {
    guard let pin = Pin1(digits: digits) else {
      fatalError("test PIN must be valid")
    }
    return pin
  }

  private static func fingerprint(_ digits: String, _ serial: ChipSerial) -> PinFingerprint {
    pin(digits).fingerprint(boundTo: serial)
  }

  private static func spentProbe() throws -> RetryProbeOutcome {
    let spent = try #require(RetryCount(attemptsRemaining: RetryCount.pristineAllowance - 1))
    return .remaining(spent)
  }

  /// True when the optional carried a PIN (consuming it either way).
  private func present(_ candidate: consuming Pin1?) -> Bool {
    if let value = candidate {
      _ = value
      return true
    }
    return false
  }

  private func accept(
    _ digits: String,
    _ serial: ChipSerial,
    in memory: Pin1Memory,
    owner: Pin1Memory.Owner = Pin1Memory.Owner()
  ) {
    guard
      let acceptance = memory.acceptance(
        of: Self.pin(digits), serial: serial, after: .verified, owner: owner)
    else {
      Issue.record("a verified probe permits holding")
      return
    }
    memory.commit(acceptance)
  }

  @Test
  internal func candidateSurvivesCheckoutUntilVerifyDecidesIt() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    #expect(memory.stageCandidate(digits: Self.digits, serial: card, operationID: UUID()))
    for _ in repeatElement((), count: Self.reuses) {
      let found = present(memory.checkoutCandidate(serial: card))
      #expect(found)
    }
    #expect(memory.holdsValue(serial: card))
    let accepted = present(memory.checkoutAccepted(serial: card))
    #expect(!accepted)
  }

  @Test
  internal func stagingRefusesDigitsThatAreNotAPin1() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    #expect(!memory.stageCandidate(digits: "12a4", serial: card, operationID: UUID()))
    #expect(!memory.holdsValue(serial: card))
  }

  @Test
  internal func commitPromotesTheCandidateToAccepted() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    memory.stageCandidate(digits: Self.digits, serial: card, operationID: UUID())
    guard let candidate = memory.checkoutCandidate(serial: card) else {
      Issue.record("expected the staged candidate")
      return
    }
    let owner = Pin1Memory.Owner()
    guard
      let acceptance = memory.acceptance(
        of: candidate, serial: card, after: .verified, owner: owner)
    else {
      Issue.record("a verified probe permits holding")
      return
    }
    let early = present(memory.checkoutAccepted(serial: card))
    #expect(!early)
    memory.commit(acceptance)

    let candidateLeft = present(memory.checkoutCandidate(serial: card))
    #expect(!candidateLeft)
    guard let reused = memory.checkoutAccepted(serial: card) else {
      Issue.record("expected the accepted PIN")
      return
    }
    #expect(reused.fingerprint(boundTo: card) == Self.fingerprint(Self.digits, card))
  }

  @Test
  internal func acceptedValueIsReusedAcrossCheckouts() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    accept(Self.digits, card, in: memory)
    for _ in repeatElement((), count: Self.reuses) {
      let found = present(memory.checkoutAccepted(serial: card))
      #expect(found)
    }
  }

  @Test
  internal func valuesAreKeyedByTheFullChipSerial() {
    // Both serials print the same nine characters; only the chip serial
    // tells the two cards apart.
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETICA-TEST00001")
    let lookalike = Self.serial("SYNTHETICB-TEST00001")
    #expect(PrintedSerial(chipSerial: card) == PrintedSerial(chipSerial: lookalike))
    accept(Self.digits, card, in: memory)
    let wrongCard = present(memory.checkoutAccepted(serial: lookalike))
    #expect(!wrongCard)
    #expect(!memory.holdsValue(serial: lookalike))
  }

  @Test
  internal func acceptedValuesForDifferentCardsAreIndependent() {
    let memory = Pin1Memory()
    let first = Self.serial("SYNTHETIC-A")
    let second = Self.serial("SYNTHETIC-B")
    accept(Self.digits, first, in: memory)
    accept(Self.otherDigits, second, in: memory)
    memory.clear(serial: first)
    let firstLeft = present(memory.checkoutAccepted(serial: first))
    #expect(!firstLeft)
    guard let secondPin = memory.checkoutAccepted(serial: second) else {
      Issue.record("expected the second card's accepted PIN")
      return
    }
    #expect(secondPin.fingerprint(boundTo: second) == Self.fingerprint(Self.otherDigits, second))
  }

  @Test
  internal func onlyOneCandidateExistsAcrossCards() {
    let memory = Pin1Memory()
    let first = Self.serial("SYNTHETIC-A")
    let second = Self.serial("SYNTHETIC-B")
    memory.stageCandidate(digits: Self.digits, serial: first, operationID: UUID())
    let otherCard = present(memory.checkoutCandidate(serial: second))
    #expect(!otherCard)
    #expect(!memory.holdsValue(serial: first))
  }

  @Test
  internal func askingAboutAnotherCardKeepsAcceptedValues() {
    let memory = Pin1Memory()
    let first = Self.serial("SYNTHETIC-A")
    let second = Self.serial("SYNTHETIC-B")
    accept(Self.digits, first, in: memory)
    memory.stageCandidate(digits: Self.digits, serial: second, operationID: UUID())
    #expect(memory.holdsValue(serial: first))
    #expect(!memory.holdsValue(serial: second))
  }

  @Test
  internal func cancellationDropsOnlyTheCandidateItsSheetStaged() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    let staged = UUID()
    memory.stageCandidate(digits: Self.digits, serial: card, operationID: staged)
    memory.cancelCandidate(operationID: UUID())
    #expect(memory.holdsValue(serial: card))
    memory.cancelCandidate(operationID: staged)
    #expect(!memory.holdsValue(serial: card))
  }

  @Test
  internal func clearCandidateKeepsAnAcceptedValue() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    accept(Self.digits, card, in: memory)
    memory.clearCandidate(serial: card)
    let kept = present(memory.checkoutAccepted(serial: card))
    #expect(kept)

    let other = Self.serial("SYNTHETIC-B")
    memory.stageCandidate(digits: Self.digits, serial: other, operationID: UUID())
    memory.clearCandidate(serial: other)
    #expect(!memory.holdsValue(serial: other))
  }

  @Test
  internal func aSpentCounterDropsTheAcceptedValueAndRefusesAcceptance() throws {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    accept(Self.digits, card, in: memory)
    let spent = try Self.spentProbe()
    #expect(!memory.retain(after: spent, serial: card))
    let dropped = present(memory.checkoutAccepted(serial: card))
    #expect(!dropped)
    #expect(
      memory.acceptance(
        of: Self.pin(Self.digits), serial: card, after: spent, owner: Pin1Memory.Owner())
        == nil)
  }

  @Test
  internal func aSpentCounterKeepsATypedCandidate() throws {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    memory.stageCandidate(digits: Self.digits, serial: card, operationID: UUID())
    #expect(!memory.retain(after: try Self.spentProbe(), serial: card))
    let kept = present(memory.checkoutCandidate(serial: card))
    #expect(kept)
  }

  @Test
  internal func aPristineCounterKeepsTheAcceptedValue() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    accept(Self.digits, card, in: memory)
    #expect(memory.retain(after: .verified, serial: card))
    let kept = present(memory.checkoutAccepted(serial: card))
    #expect(kept)
  }

  @Test
  internal func anUncommittedAcceptanceHoldsNothing() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    let acceptance = memory.acceptance(
      of: Self.pin(Self.digits), serial: card, after: .verified, owner: Pin1Memory.Owner())
    #expect(acceptance != nil)
    #expect(!memory.holdsValue(serial: card))
  }

  @Test
  internal func anOlderOwnersTeardownKeepsANewerOwnersAcceptedValue() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    let older = Pin1Memory.Owner()
    let newer = Pin1Memory.Owner()
    accept(Self.digits, card, in: memory, owner: older)
    accept(Self.otherDigits, card, in: memory, owner: newer)
    memory.clear(serial: card, ownedBy: older)
    guard let reused = memory.checkoutAccepted(serial: card) else {
      Issue.record("expected the newer owner's accepted PIN")
      return
    }
    #expect(reused.fingerprint(boundTo: card) == Self.fingerprint(Self.otherDigits, card))
    memory.clear(serial: card, ownedBy: newer)
    #expect(!memory.holdsValue(serial: card))
  }

  @Test
  internal func anOwnersTeardownKeepsACandidate() {
    let memory = Pin1Memory()
    let card = Self.serial("SYNTHETIC-A")
    memory.stageCandidate(digits: Self.digits, serial: card, operationID: UUID())
    memory.clear(serial: card, ownedBy: Pin1Memory.Owner())
    #expect(memory.holdsValue(serial: card))
  }

  @Test
  internal func clearAllDropsEveryCard() {
    let memory = Pin1Memory()
    let first = Self.serial("SYNTHETIC-A")
    let second = Self.serial("SYNTHETIC-B")
    accept(Self.digits, first, in: memory)
    memory.stageCandidate(digits: Self.digits, serial: second, operationID: UUID())
    memory.clearAll()
    #expect(!memory.holdsValue(serial: first))
    #expect(!memory.holdsValue(serial: second))
  }
}
