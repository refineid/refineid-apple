// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The key at the right end of the window's toolbar, in the title bar.
  ///
  /// While a card is in this Mac's reader it shows two keys, one for each
  /// PIN, and opens the PIN codes window. The keys are red while a code
  /// of the card is below the retry floor, since the card cannot be used
  /// until that code is reset, and the PIN codes window opens by itself
  /// when the reading says so. With no card in the reader it shows
  /// nothing.
  internal struct PinCodesButton: View {
    private static let pinCodesSymbol = "key.2.on.ring"

    @ObservedObject private var cardPresence = CardPresence.shared
    @ObservedObject private var demoMode = DemoMode.shared
    @ObservedObject private var retryHealth = CredentialRetryHealth.shared
    private let selection = CardSelection.shared
    /// Whether the PIN codes window has opened by itself for the card now
    /// in the reader; it opens once per insertion, so a window the holder
    /// closed stays closed through later readings of the same card.
    @State private var openedForCard = false
    @Environment(\.openWindow)
    private var openWindow

    /// Whether a card is in this Mac's reader, or in a demonstration's
    /// virtual one.
    private var readerCardIsPresent: Bool {
      #if DEBUG && REFINEID_REMOTE_CARD
        if DemoPairedPhone.isShown { return false }
      #endif
      return demoMode.isActive ? demoMode.isReaderCardPresent : cardPresence.isReaderCardPresent
    }

    /// Whether a code of the card in the reader is below the retry floor.
    private var cardNeedsReset: Bool {
      readerCardIsPresent && retryHealth.level == .critical
    }

    internal var body: some View {
      // The observers sit outside the card branch: they must see the
      // insertion that mounts the key, and the removal that takes it
      // away with them.
      Group {
        if readerCardIsPresent {
          Button {
            openWindow(id: PinCodesWindow.windowID)
          } label: {
            Image(systemName: Self.pinCodesSymbol)
              .foregroundStyle(Self.cardStyle(needsReset: cardNeedsReset))
              .replacingSymbol()
          }
          // The PIN codes belong to one card; with several, to the one chosen.
          .disabled(selection.awaitsChoice)
          .help(Text("PIN Codes"))
          .accessibilityLabel(Text("PIN Codes"))
          .accessibilityValue(Self.cardValue(needsReset: cardNeedsReset))
          .accessibilityIdentifier("manageCard")
        }
      }
      .onChange(of: cardNeedsReset, initial: true) { _, needsReset in
        if needsReset, !openedForCard {
          openedForCard = true
          openWindow(id: PinCodesWindow.windowID)
        }
      }
      .onChange(of: selection.target) {
        // The keys show the attempts of the card now used.
        if readerCardIsPresent {
          retryHealth.refreshFromReader()
        }
      }
      .onChange(of: readerCardIsPresent) { _, present in
        if !present {
          openedForCard = false
        }
      }
    }

    private static func cardStyle(needsReset: Bool) -> AnyShapeStyle {
      needsReset ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
    }

    private static func cardValue(needsReset: Bool) -> Text {
      needsReset ? Text("A PIN code needs a reset") : Text(verbatim: "")
    }
  }

#endif
