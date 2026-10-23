// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import SwiftUI

  /// The button at the right end of the window's toolbar, in the title bar.
  ///
  /// While a card is in this Mac's reader it shows two keys, one for each
  /// PIN, and opens the PIN codes window: the local card overrides remote
  /// use then (STPA CC-86), so the switch has nothing to switch. Otherwise
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
    @Environment(\.openWindow)
    private var openWindow

    /// Whether a card is in this Mac's reader, or in a demonstration's
    /// virtual one.
    private var readerCardIsPresent: Bool {
      demoMode.isActive ? demoMode.isReaderCardPresent : cardPresence.isReaderCardPresent
    }

    private var state: RemoteUseState {
      RemoteUseState.derive(
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
          .foregroundStyle(readerCardIsPresent ? AnyShapeStyle(.secondary) : Self.style(state.tone))
          .replacingSymbol()
      }
      .help(readerCardIsPresent ? Text("PIN Codes") : Text(state.help))
      .accessibilityLabel(readerCardIsPresent ? Text("PIN Codes") : Text(RemoteUseState.label))
      .accessibilityValue(readerCardIsPresent ? Text(verbatim: "") : Text(state.value))
      .accessibilityAddTraits(readerCardIsPresent ? [] : .isToggle)
      .accessibilityIdentifier(readerCardIsPresent ? "manageCard" : "remoteUseSwitch")
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
