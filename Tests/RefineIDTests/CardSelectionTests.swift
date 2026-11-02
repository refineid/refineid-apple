// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineIDTestHost

/// Which card the window's card operations go to.
@Suite
@MainActor
internal struct CardSelectionTests {
  private static let firstSlot = "Contact Reader"
  private static let secondSlot = "Contactless Reader"

  private static let citizen = SelectableCard(
    tokenID: "citizen-token", slotName: secondSlot, holderLine: "Virtanen Liisa")
  private static let organisation = SelectableCard(
    tokenID: "organisation-token", slotName: firstSlot,
    holderLine: "Virtanen Liisa, Testiorganisaatio Oy")

  @Test("one card is the target without a choice")
  internal func oneCardIsImplicit() {
    let selection = CardSelection()
    selection.show([Self.citizen])
    #expect(selection.target == .slot(Self.secondSlot))
    #expect(!selection.awaitsChoice)
    selection.choose(Self.citizen.tokenID)
    #expect(selection.chosen == nil)
  }

  @Test("two cards have no target until one is chosen")
  internal func twoCardsAwaitChoice() {
    let selection = CardSelection()
    selection.show([Self.citizen, Self.organisation])
    #expect(selection.chosen == nil)
    #expect(selection.target == .unchosen)
    #expect(selection.awaitsChoice)
    selection.choose(Self.organisation.tokenID)
    #expect(selection.target == .slot(Self.firstSlot))
    #expect(!selection.awaitsChoice)
    selection.choose(Self.citizen.tokenID)
    #expect(selection.target == .slot(Self.secondSlot))
  }

  @Test("a chosen card that leaves takes the choice with it")
  internal func chosenCardLeaving() {
    let selection = CardSelection()
    let third = SelectableCard(
      tokenID: "third-token", slotName: "Third Reader", holderLine: "Aalto Aino")
    selection.show([Self.citizen, Self.organisation, third])
    selection.choose(Self.citizen.tokenID)
    selection.show([Self.organisation, third])
    #expect(selection.chosen == nil)
    #expect(selection.target == .unchosen)
  }

  @Test("the other card leaving leaves one card, and its return asks again")
  internal func otherCardLeavingAndReturning() {
    let selection = CardSelection()
    selection.show([Self.citizen, Self.organisation])
    selection.choose(Self.citizen.tokenID)
    selection.show([Self.citizen])
    #expect(selection.target == .slot(Self.secondSlot))
    selection.show([Self.citizen, Self.organisation])
    #expect(selection.target == .unchosen)
  }

  @Test("another card in the chosen card's slot is not chosen")
  internal func replacedCardInSameSlot() {
    let selection = CardSelection()
    selection.show([Self.citizen, Self.organisation])
    selection.choose(Self.citizen.tokenID)
    let replacement = SelectableCard(
      tokenID: "replacement-token", slotName: Self.secondSlot, holderLine: "Korhonen Matti")
    selection.show([replacement, Self.organisation])
    #expect(selection.target == .unchosen)
  }

  @Test("a card awaiting activation is the target of the activation form")
  internal func activationSlotIsTarget() {
    let selection = CardSelection()
    selection.show([Self.citizen])
    selection.activationSlots = [Self.firstSlot]
    #expect(selection.target == .slot(Self.firstSlot))
    selection.activationSlots = [Self.firstSlot, Self.secondSlot]
    #expect(selection.target == .unchosen)
  }

  @Test("no card listed leaves every reader open")
  internal func noCardListed() {
    #expect(ReaderTarget.resolve(activationSlots: [], cards: [], chosen: nil) == .anyReader)
  }

  @Test("operations reach only the target's slot")
  internal func targetAdmitsSlots() {
    let occupied = [Self.firstSlot, Self.secondSlot]
    #expect(ReaderTarget.anyReader.admits(occupied) == occupied)
    #expect(ReaderTarget.slot(Self.secondSlot).admits(occupied) == [Self.secondSlot])
    #expect(ReaderTarget.slot("Gone Reader").admits(occupied).isEmpty)
    #expect(ReaderTarget.unchosen.admits(occupied).isEmpty)
  }

  @Test("lines are ordered by holder line in Finnish collation")
  internal func orderedByName() {
    let names = [
      "\u{D6}hman Olli",
      "Zetterberg Ville",
      "\u{C4}yr\u{E4}m\u{F6} Matti",
      "Aalto Aino",
      "\u{C5}berg Eva",
    ]
    let cards = names.enumerated().map { index, name in
      SelectableCard(tokenID: "token-\(index)", slotName: "Reader \(index)", holderLine: name)
    }
    #expect(
      CardSelection.ordered(cards).map(\.holderLine) == [
        "Aalto Aino",
        "Zetterberg Ville",
        "\u{C5}berg Eva",
        "\u{C4}yr\u{E4}m\u{F6} Matti",
        "\u{D6}hman Olli",
      ])
  }

  @Test("equal names keep a stable order by organisation, then by slot")
  internal func tiesAreStable() {
    let twin = SelectableCard(
      tokenID: "twin-token", slotName: Self.firstSlot, holderLine: "Virtanen Liisa")
    let ordered = CardSelection.ordered([Self.organisation, Self.citizen, twin])
    #expect(
      ordered.map(\.tokenID) == [twin.tokenID, Self.citizen.tokenID, Self.organisation.tokenID])
    #expect(CardSelection.ordered(Array(ordered.reversed())) == ordered)
  }

  @Test("the window keeps its order while cards come and go")
  internal func orderDoesNotFollowArrival() {
    let selection = CardSelection()
    selection.show([Self.organisation, Self.citizen])
    let first = selection.cards
    selection.show([Self.citizen, Self.organisation])
    #expect(selection.cards == first)
  }
}
