// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import SwiftUI

  /// The button at the right end of the window's toolbar, in the title bar.
  ///
  /// While a card is in this Mac's reader it is the PIN codes key: the
  /// local card suspends remote use then (STPA CC-86, CC-102), and the
  /// switch keeps its state until the card leaves. Otherwise it is the
  /// remote-use switch: a click turns remote use on or off, and the
  /// symbol is the state (STPA CC-95). The help and the accessibility
  /// value name the state in words, the blocked state's cause included, so
  /// no state rests on colour alone.
  internal struct RemoteUseButton: View {
    private let remoteUse = RemoteUseSwitch.shared
    private let registry = PersistentTokenRegistry.shared

    @ObservedObject private var cardPresence = CardPresence.shared
    @ObservedObject private var demoMode = DemoMode.shared

    /// Whether a card is in this Mac's reader, or in a demonstration's
    /// virtual one.
    private var readerCardIsPresent: Bool {
      #if DEBUG
        if DemoPairedPhone.isShown { return false }
      #endif
      return demoMode.isActive ? demoMode.isReaderCardPresent : cardPresence.isReaderCardPresent
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
      if readerCardIsPresent {
        PinCodesButton()
      } else {
        Button {
          remoteUse.toggle()
        } label: {
          Image(systemName: state.symbolName)
            .foregroundStyle(Self.style(state.tone))
            .replacingSymbol()
        }
        .help(Text(state.help))
        .accessibilityLabel(Text(RemoteUseState.label))
        .accessibilityValue(Text(state.value))
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("remoteUseSwitch")
      }
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
