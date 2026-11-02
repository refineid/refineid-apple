// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Which reader slots a card operation the app starts may reach.
///
/// With several cards in readers, the card an operation spends a PIN on is
/// the one the holder chose, never whichever card answers first.
internal enum ReaderTarget: Equatable, Sendable {
  /// Every occupied reader slot, tried in the system's naming order.
  case anyReader

  /// Only the slot of this name.
  case slot(String)

  /// No slot: several cards are present and none is chosen.
  case unchosen

  /// The target for the cards the window lists.
  ///
  /// A card awaiting activation is the one the activation form acts on, so
  /// its slot is the target while it is the only one; two such cards leave
  /// no target. Otherwise one listed card is the target by itself, several
  /// need the holder's choice, and none leaves every slot open.
  internal static func resolve(
    activationSlots: [String],
    cards: [SelectableCard],
    chosen: String?
  ) -> Self {
    if !activationSlots.isEmpty {
      return activationSlots.count == 1 ? .slot(activationSlots[0]) : .unchosen
    }
    switch cards.count {
    case 0:
      return .anyReader

    case 1:
      return .slot(cards[0].slotName)

    default:
      guard let chosen, let card = cards.first(where: { $0.tokenID == chosen }) else {
        return .unchosen
      }
      return .slot(card.slotName)
    }
  }

  /// The slot names among `occupied` an operation may use, in their order.
  internal func admits(_ occupied: [String]) -> [String] {
    switch self {
    case .anyReader:
      occupied

    case .slot(let name):
      occupied.filter { $0 == name }

    case .unchosen:
      []
    }
  }
}
