// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The identity lines of two or more cards, each with a Select button.
  ///
  /// None is chosen until the holder clicks one: the card a PIN is spent on
  /// is the holder's choice, never a default. The chosen line shows a check
  /// mark in place of its button.
  internal struct CardChoiceList: View {
    internal let selection: CardSelection

    internal var body: some View {
      ForEach(selection.cards, id: \.tokenID) { card in
        HStack {
          Text(verbatim: card.holderLine)
            .frame(maxWidth: .infinity, alignment: .leading)
          if selection.chosen == card.tokenID {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.tint)
              .accessibilityLabel(Text("Selected"))
          } else {
            Button("Select") { selection.choose(card.tokenID) }
              .accessibilityLabel(Text("Select \(card.holderLine)"))
          }
        }
      }
      .accessibilityIdentifier("cardChoice")
    }
  }

#endif
