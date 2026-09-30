// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The one status control: PIN health on the key, link state on the waves.
  internal struct StatusSettingsGlyph: View {
    private enum Layout {
      static let glyphPointSize: CGFloat = 22
    }

    private static var symbolName: String {
      #if REFINEID_REMOTE_CARD
        "key.radiowaves.forward"
      #else
        "key"
      #endif
    }

    internal let pinLevel: CredentialRetryHealth.Level?
    internal let routeAvailable: Bool

    internal var body: some View {
      Image(systemName: Self.symbolName)
        .font(.system(size: Layout.glyphPointSize))
        .symbolRenderingMode(.palette)
        .foregroundStyle(keyColor, waveColor)
        .replacingSymbolPlainly()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Change or Reset PINs"))
        .accessibilityValue(accessibilityValue)
    }

    private var isRemoteHolderConnected: Bool {
      #if REFINEID_REMOTE_CARD
        if PersistentTokenRegistry.shared.holderIsAdvertising {
          return true
        }
        return RappAutoPairingService.shared.remoteDevices.contains { $0.role == .holder }
      #else
        return false
      #endif
    }

    private var accessibilityValue: String {
      #if REFINEID_REMOTE_CARD
        let link =
          isRemoteHolderConnected
          ? String(localized: "Phone connected")
          : String(localized: "Phone not connected")
        if let pins = pinLevel?.accessibilityValue {
          return pins + ", " + link
        }
        return link
      #else
        return pinLevel?.accessibilityValue ?? ""
      #endif
    }

    /// Green, yellow, or red from the card's retry class; grey without a card.
    private var keyColor: Color {
      guard routeAvailable, let pinLevel else { return .secondary }
      return pinLevel.color
    }

    /// Green while a paired phone holder is connected; grey when it is not.
    private var waveColor: Color {
      isRemoteHolderConnected ? .green : .secondary
    }
  }

#endif
