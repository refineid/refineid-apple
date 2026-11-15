// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import SwiftUI

  /// The Remote key: idle, or green with a check once a pair is live.
  internal struct RemotePairingGlyph: View {
    private enum Layout {
      static let badgeGlyphSize: CGFloat = 12
    }

    /// Whether this device currently has a usable pairing.
    internal let isConnected: Bool

    internal var body: some View {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: "key.radiowaves.forward")
          .font(.system(size: PersonRowLabel.iconPointSize))
          .symbolRenderingMode(.monochrome)
          .replacingSymbolPlainly()
          .foregroundStyle(isConnected ? Color.green : Color.secondary)
          .accessibilityHidden(true)
        if isConnected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: Layout.badgeGlyphSize, weight: .bold))
            .foregroundStyle(.green)
            .background(.background, in: Circle())
            .accessibilityHidden(true)
        }
      }
    }
  }
#endif
