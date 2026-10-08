// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The identity submenu view displaying cardholder photo, details, and forget action.
internal struct CardIdentitySubmenuView: View {
  // MARK: - Properties

  internal let holder: String
  internal let identifier: String?
  internal let onForget: (() -> Void)?
  internal let onReadPhoto: ((String?) async -> CardCredentialsView.CardPhotoReadResult)?

  @Environment(\.dismiss)
  private var dismiss

  @State private var showsForgetConfirmation = false

  // MARK: - Body

  internal var body: some View {
    Form {
      CardIdentityPhotoView(holder: holder, onReadPhoto: onReadPhoto)
      detailsSection
      if let onForget {
        removeSection(action: onForget)
      }
    }
    .navigationTitle(String(localized: "Identity"))
  }

  private var detailsSection: some View {
    Section {
      LabeledContent(String(localized: "Person")) {
        Text(holder)
          .textSelection(.enabled)
          .accessibilityIdentifier("identityStatus")
      }
      if let identifier, !identifier.isEmpty {
        LabeledContent(
          String(localized: "identity.identifier", defaultValue: "Identifier")
        ) {
          Text(identifier)
            .textSelection(.enabled)
            .accessibilityIdentifier("identityIdentifier")
        }
      }
    }
  }

  // MARK: - Methods

  private func removeSection(action: @escaping () -> Void) -> some View {
    Section {
      Button(role: .destructive) {
        showsForgetConfirmation = true
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
      .alert(
        "Forget identity?",
        isPresented: $showsForgetConfirmation
      ) {
        Button("Cancel", role: .cancel) {
          // Keep current identity
        }
        Button("Forget", role: .destructive) {
          action()
          dismiss()
        }
      }
    }
  }
}
