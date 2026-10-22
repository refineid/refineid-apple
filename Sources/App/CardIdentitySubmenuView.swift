// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The identity submenu view displaying the cardholder photo and the forget action.
internal struct CardIdentitySubmenuView: View {
  // MARK: - Properties

  internal let holder: String
  internal let onForget: (() -> Void)?
  internal let onReadPhoto: ((String?) async -> CardCredentialsView.CardPhotoReadResult)?

  @Environment(\.dismiss)
  private var dismiss

  // MARK: - Body

  internal var body: some View {
    Form {
      CardIdentityPhotoView(holder: holder, onReadPhoto: onReadPhoto)
      if let onForget {
        removeSection(action: onForget)
      }
    }
    .navigationTitle(String(localized: "Identity"))
  }

  // MARK: - Methods

  private func removeSection(action: @escaping () -> Void) -> some View {
    Section {
      Button(role: .destructive) {
        action()
        dismiss()
      } label: {
        Label {
          Text(String(localized: "identity.remove", defaultValue: "Remove identity from phone"))
        } icon: {
          Image(systemName: "person.badge.minus")
            .foregroundStyle(.red)
            .accessibilityHidden(true)
        }
      }
      .accessibilityIdentifier("forgetCardIdentityButton")
    }
  }
}
