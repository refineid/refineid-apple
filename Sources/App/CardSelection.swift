// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Observation

  /// The cards in this Mac's readers and the one the holder chose.
  ///
  /// One card needs no choice. With two or more, none is chosen until the
  /// holder picks a line, and a chosen card that leaves takes the choice
  /// with it. Every card operation the window starts goes to ``target``.
  @MainActor
  @Observable
  internal final class CardSelection {
    /// The one selection the window and its card operations share.
    internal static let shared = CardSelection()

    /// The collation the lines are ordered by: Finnish, where the letters
    /// a-ring, a-diaeresis and o-diaeresis follow z, as they do in Swedish.
    nonisolated private static let collation = Locale(identifier: "fi_FI")

    /// How many cards it takes for the holder to choose one.
    private static let choiceCount = 2

    /// The listed cards, ordered by holder line.
    internal private(set) var cards: [SelectableCard] = []

    /// The token of the card the holder chose; nil while none is.
    internal private(set) var chosen: String?

    /// The reader slots of cards awaiting activation.
    internal var activationSlots: [String] = []

    /// Whether the holder must choose a card before it can be used.
    internal var awaitsChoice: Bool {
      target == .unchosen
    }

    /// The slots a card operation may reach now.
    internal var target: ReaderTarget {
      ReaderTarget.resolve(activationSlots: activationSlots, cards: cards, chosen: chosen)
    }

    /// `cards` ordered by holder line in Finnish collation; equal lines
    /// by reader slot, then by token.
    nonisolated internal static func ordered(_ cards: [SelectableCard]) -> [SelectableCard] {
      cards.sorted { lhs, rhs in
        let byName = lhs.holderLine.compare(
          rhs.holderLine, options: [.caseInsensitive], range: nil, locale: collation)
        if byName != .orderedSame {
          return byName == .orderedAscending
        }
        if lhs.slotName != rhs.slotName {
          return lhs.slotName < rhs.slotName
        }
        return lhs.tokenID < rhs.tokenID
      }
    }

    /// Lists `read`: ordered by holder line, the choice kept only while
    /// its card is still among two or more.
    internal func show(_ read: [SelectableCard]) {
      let ordered = Self.ordered(read)
      if let chosen,
        ordered.count < Self.choiceCount || !ordered.contains(where: { $0.tokenID == chosen })
      {
        self.chosen = nil
      }
      if ordered != cards {
        cards = ordered
      }
    }

    /// Chooses the listed card with `tokenID`; one not listed chooses
    /// nothing.
    internal func choose(_ tokenID: String?) {
      guard
        cards.count >= Self.choiceCount,
        let tokenID,
        cards.contains(where: { $0.tokenID == tokenID })
      else {
        chosen = nil
        return
      }
      chosen = tokenID
    }

    /// Reads the holder line of every local card token in `tokenIDs` and
    /// lists them once all are read.
    ///
    /// `slotName` answers where a token was minted; a token with no slot,
    /// such as the paired phone's, is not a card in this Mac's reader.
    internal func reload(tokenIDs: [String], slotName: (String) -> String?) async {
      let located = tokenIDs.compactMap { tokenID -> (String, String)? in
        guard
          CardTokenNamespace.owns(tokenIdentifier: tokenID),
          let slot = slotName(tokenID)
        else { return nil }
        return (tokenID, slot)
      }
      let read = await Task.detached(priority: .utility) {
        located.compactMap { tokenID, slot -> SelectableCard? in
          PublishedIdentityName.name(ofTokenIdentifier: tokenID).map { name in
            SelectableCard(tokenID: tokenID, slotName: slot, holderLine: name)
          }
        }
      }.value
      guard !Task.isCancelled else { return }
      show(read)
    }
  }

#endif
