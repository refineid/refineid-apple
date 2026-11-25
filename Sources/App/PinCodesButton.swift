// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The key beside the local card's identity line.
  ///
  /// While a card is in this Mac's reader it shows two keys, one for each
  /// PIN, and opens the PIN codes window. The keys are red while a code
  /// of the card is below the retry floor, since the card cannot be used
  /// until that code is reset, and the PIN codes window opens by itself
  /// when the reading says so. With no card in the reader it shows
  /// nothing.
  internal struct PinCodesButton: View {
    private static let pinCodesSymbol = "key.2.on.ring.fill"

    @ObservedObject private var cardPresence = CardPresence.shared
    @ObservedObject private var demoMode = DemoMode.shared
    @ObservedObject private var retryHealth = CredentialRetryHealth.shared
    private let selection = CardSelection.shared
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

    /// Whether the card's initial PIN 2 must be changed before signing.
    private var cardNeedsPin2Change: Bool {
      readerCardIsPresent && retryHealth.pin2RequiresChangeBeforeSigning
    }

    /// Whether the card needs the PIN codes window opened automatically.
    private var opensPinCodesAutomatically: Bool {
      Self.opensAutomatically(
        readerCardIsPresent: readerCardIsPresent,
        awaitsChoice: selection.awaitsChoice,
        level: retryHealth.level,
        pin2RequiresChange: retryHealth.pin2RequiresChangeBeforeSigning
      )
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
              .font(.title2)
              .foregroundStyle(
                Self.cardStyle(
                  needsReset: cardNeedsReset, needsPin2Change: cardNeedsPin2Change)
              )
              .replacingSymbol()
          }
          .buttonStyle(.plain)
          // The PIN codes belong to one card; with several, to the one chosen.
          .disabled(selection.awaitsChoice)
          .help(Text("PIN Codes"))
          .accessibilityLabel(Text("PIN Codes"))
          .accessibilityValue(
            Self.cardValue(
              needsReset: cardNeedsReset, needsPin2Change: cardNeedsPin2Change)
          )
          .accessibilityIdentifier("pinCodesButton")
        }
      }
      .onChange(of: opensPinCodesAutomatically, initial: true) { _, opensAutomatically in
        if opensAutomatically, !retryHealth.openedForCard {
          retryHealth.openedForCard = true
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
          retryHealth.openedForCard = false
        }
      }
    }

    internal static func opensAutomatically(
      readerCardIsPresent: Bool,
      awaitsChoice: Bool,
      level: CredentialRetryHealth.Level?,
      pin2RequiresChange: Bool
    ) -> Bool {
      guard readerCardIsPresent, !awaitsChoice else { return false }
      return level == .critical || pin2RequiresChange
    }

    internal static func cardStyle(needsReset: Bool, needsPin2Change: Bool) -> AnyShapeStyle {
      if needsReset {
        return AnyShapeStyle(.red)
      }
      if needsPin2Change {
        return AnyShapeStyle(.orange)
      }
      return AnyShapeStyle(.primary)
    }

    internal static func cardValue(needsReset: Bool, needsPin2Change: Bool) -> Text {
      if needsReset {
        return Text("A PIN code needs a reset")
      }
      if needsPin2Change {
        return Text("Change PIN 2 so you can sign documents.")
      }
      return Text(verbatim: "")
    }
  }

#endif
