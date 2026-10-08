// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The identity row on the main screen: the holder this phone
/// registered, and on iOS the way into the identity submenu.
internal struct CardIdentitySection: View {
  /// The complete holder name read from the primed identity certificate.
  internal let holder: String

  private var row: some View {
    MenuRow(holder, systemImage: "person", tint: .accentColor)
      .titleIdentifier("identityStatus")
  }

  internal var body: some View {
    Section {
      #if os(iOS)
        NavigationLink(value: CardCredentialsView.Route.identity(.phone(holder: holder))) {
          row
        }
        .accessibilityIdentifier("identitySubmenuButton")
      #else
        row
      #endif
    } header: {
      CompactSectionHeader(title: String(localized: "Identity"))
    }
  }
}
