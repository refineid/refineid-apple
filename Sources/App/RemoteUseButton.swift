// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import SwiftUI

  /// The remote-use switch at the right end of the window's toolbar, in the
  /// title bar: a click turns remote use on or off, and the symbol is the
  /// state (STPA CC-95).
  ///
  /// The help and the accessibility value name the state in words, the
  /// blocked state's cause included, so no state rests on colour alone.
  internal struct RemoteUseButton: View {
    private let remoteUse = RemoteUseSwitch.shared
    private let registry = PersistentTokenRegistry.shared

    private var state: RemoteUseState {
      RemoteUseState.derive(
        isOn: remoteUse.isOn,
        sessionOpen: registry.holderSessionOpen,
        blockage: remoteUse.blockage)
    }

    internal var body: some View {
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
