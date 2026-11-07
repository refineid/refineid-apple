// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// A card form's one action: full width and large on iPhone and iPad,
/// centred under the last group on the Mac.
internal struct CardFormButton: View {
  internal let title: LocalizedStringKey
  internal let identifier: String
  internal let enabled: Bool

  /// Why the button is off while every entry is valid; nil when it is not.
  internal var blockedReason: String?

  internal let action: () -> Void

  internal var body: some View {
    button
    if let blockedReason {
      CredentialOutcomeText(message: blockedReason, tone: .failure)
        .accessibilityIdentifier("managementBlockedReason")
    }
  }

  private var button: some View {
    Button(action: action) {
      Text(title)
        #if os(iOS)
          .frame(maxWidth: .infinity)
        #endif
    }
    .buttonStyle(.borderedProminent)
    #if os(iOS)
      .controlSize(.large)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    #else
      .frame(maxWidth: .infinity)
    #endif
    .keyboardShortcut(.defaultAction)
    .disabled(!enabled)
    .accessibilityIdentifier(identifier)
  }
}
