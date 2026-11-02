// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The identity lines of two or more cards, one radio button each.
  ///
  /// None is chosen until the holder clicks one: the card a PIN is spent on
  /// is the holder's choice, never a default.
  internal struct CardChoiceList: View {
    internal let selection: CardSelection

    private var chosen: Binding<String?> {
      Binding(
        get: { selection.chosen },
        set: { selection.choose($0) }
      )
    }

    internal var body: some View {
      Picker("Card", selection: chosen) {
        ForEach(selection.cards, id: \.tokenID) { card in
          Text(card.holderLine)
            .tag(Optional(card.tokenID))
            .accessibilityLabel(Text(verbatim: card.holderLine))
        }
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier("cardChoice")
    }
  }

#endif
