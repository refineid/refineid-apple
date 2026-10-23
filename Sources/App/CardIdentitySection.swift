// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The identity row on the main screen: the holder this phone
/// registered, and the button that removes the identity from the phone.
internal struct CardIdentitySection: View {
  private enum Layout {
    static let tapTargetSide: CGFloat = 44
  }

  /// The complete holder name read from the primed identity certificate.
  internal let holder: String

  /// Removes the identity from the phone at once.
  internal let onRemove: () -> Void

  internal var body: some View {
    Section {
      MenuRow(holder, systemImage: "person", tint: .accentColor) {
        removeButton
      }
      .titleIdentifier("identityStatus")
    } header: {
      CompactSectionHeader(title: String(localized: "Identity"))
    }
  }

  private var removeButton: some View {
    Button(role: .destructive, action: onRemove) {
      Image(systemName: "minus.circle")
        .font(.title3)
        .foregroundStyle(.red)
    }
    .buttonStyle(.borderless)
    .frame(width: Layout.tapTargetSide, height: Layout.tapTargetSide)
    .contentShape(Rectangle())
    .accessibilityLabel(
      Text(String(localized: "identity.remove", defaultValue: "Remove identity from phone"))
    )
    .accessibilityIdentifier("forgetCardIdentityButton")
  }
}
