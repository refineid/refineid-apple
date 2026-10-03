// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The identity submenu view displaying cardholder details and forget action.
internal struct CardIdentitySubmenuView: View {
  internal let holder: String
  internal let identifier: String?
  internal let onForget: (() -> Void)?

  internal var body: some View {
    Form {
      Section {
        LabeledContent("Person") {
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
      if let onForget {
        Section {
          Button(role: .destructive, action: onForget) {
            HStack {
              Spacer()
              Text("Forget identity")
              Spacer()
            }
          }
          .accessibilityIdentifier("forgetCardIdentityButton")
        }
      }
    }
    .navigationTitle(String(localized: "Identity"))
  }
}
