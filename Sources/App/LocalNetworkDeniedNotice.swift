// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The local-network denial as an error, with the one click that opens
/// the settings where the holder allows it.
///
/// It clears itself once the app is active again and a new try reaches the
/// network; there is nothing to retry by hand.
internal struct LocalNetworkDeniedNotice: View {
  private enum Layout {
    static let spacing: CGFloat = 6
  }

  internal var body: some View {
    VStack(alignment: .leading, spacing: Layout.spacing) {
      Text(LocalNetworkSettings.deniedMessage)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
      Button(String(localized: "Open Settings")) {
        LocalNetworkSettings.open()
      }
      .accessibilityIdentifier("openLocalNetworkSettings")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
