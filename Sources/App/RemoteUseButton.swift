// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import SwiftUI

  /// The button at the right end of the window's toolbar, in the title bar.
  ///
  /// While a card is in this Mac's reader it shows two keys, one for each
  /// PIN, and opens the PIN codes window: the local card suspends remote
  /// use then (STPA CC-86, CC-102), and the switch keeps its state until
  /// the card leaves. The keys are red while a code of the card is below
  /// the retry floor, since the card cannot be used until that code is
  /// reset, and the PIN codes window opens by itself when the reading
  /// says so. Otherwise
  /// it is the remote-use switch: a click turns remote use on or off, and
  /// the symbol is the state (STPA CC-95). The help and the accessibility
  /// value name the state in words, the blocked state's cause included, so
  /// no state rests on colour alone.
  internal struct RemoteUseButton: View {
    private static let pinCodesSymbol = "key.2.on.ring"

    private let remoteUse = RemoteUseSwitch.shared
    private let registry = PersistentTokenRegistry.shared

    @ObservedObject private var cardPresence = CardPresence.shared
    @ObservedObject private var demoMode = DemoMode.shared
    @ObservedObject private var retryHealth = CredentialRetryHealth.shared
    @Environment(\.openWindow)
    private var openWindow

    /// Whether a card is in this Mac's reader, or in a demonstration's
    /// virtual one.
    private var readerCardIsPresent: Bool {
      #if DEBUG
        if DemoPairedPhone.isShown { return false }
      #endif
      return demoMode.isActive ? demoMode.isReaderCardPresent : cardPresence.isReaderCardPresent
    }

    /// Whether a code of the card in the reader is below the retry floor.
    private var cardNeedsReset: Bool {
      readerCardIsPresent && retryHealth.level == .critical
    }

    private var symbolStyle: AnyShapeStyle {
      readerCardIsPresent ? Self.cardStyle(needsReset: cardNeedsReset) : Self.style(state.tone)
    }

    private var symbolValue: Text {
      readerCardIsPresent ? Self.cardValue(needsReset: cardNeedsReset) : Text(state.value)
    }

    private var state: RemoteUseState {
      #if DEBUG
        if DemoPairedPhone.isShown { return .connected }
      #endif
      return RemoteUseState.derive(
        isOn: remoteUse.isOn,
        sessionOpen: registry.holderSessionOpen,
        blockage: remoteUse.blockage)
    }

    internal var body: some View {
      Button {
        if readerCardIsPresent {
          openWindow(id: PinCodesWindow.windowID)
        } else {
          remoteUse.toggle()
        }
      } label: {
        Image(systemName: readerCardIsPresent ? Self.pinCodesSymbol : state.symbolName)
          .foregroundStyle(symbolStyle)
          .replacingSymbol()
      }
      .help(readerCardIsPresent ? Text("PIN Codes") : Text(state.help))
      .accessibilityLabel(readerCardIsPresent ? Text("PIN Codes") : Text(RemoteUseState.label))
      .accessibilityValue(symbolValue)
      .onValueChange(of: cardNeedsReset) { needsReset in
        if needsReset {
          openWindow(id: PinCodesWindow.windowID)
        }
      }
      .accessibilityAddTraits(readerCardIsPresent ? [] : .isToggle)
      .accessibilityIdentifier(readerCardIsPresent ? "manageCard" : "remoteUseSwitch")
    }

    private static func cardStyle(needsReset: Bool) -> AnyShapeStyle {
      needsReset ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
    }

    private static func cardValue(needsReset: Bool) -> Text {
      needsReset ? Text("A PIN code needs a reset") : Text(verbatim: "")
    }

    private static func style(_ tone: RemoteUseState.Tone) -> AnyShapeStyle {
      switch tone {
      case .neutral:
        AnyShapeStyle(.secondary)

      case .connected:
        AnyShapeStyle(.green)

      case .warning:
        AnyShapeStyle(.orange)
      }
    }
  }

#endif
