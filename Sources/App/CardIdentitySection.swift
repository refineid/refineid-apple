// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The identity navigation row on the main screen that opens the identity submenu.
internal struct CardIdentitySection: View {
  /// The complete holder name read from the primed identity certificate.
  internal let holder: String

  /// The action to open the identity submenu.
  internal let onSelect: () -> Void

  internal var body: some View {
    Section {
      Button(action: onSelect) {
        HStack {
          Image(systemName: "person")
            .font(.system(size: PersonRowLabel.iconPointSize))
            .symbolRenderingMode(.monochrome)
            .frame(width: PersonRowLabel.iconWidth)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
          Text(String(localized: "Identity"))
          Spacer()
          Text(holder)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("identityStatus")
          Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("identitySubmenuButton")
    }
  }
}
