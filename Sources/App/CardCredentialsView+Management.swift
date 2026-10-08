// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import SwiftUI

  extension CardCredentialsView {
    internal var managementSection: some View {
      Section("Manage") {
        NavigationLink {
          CardManagementView(
            readerCardIsPresent: false,
            activationRequired: false,
            cardAccessNumber: nil
          )
        } label: {
          Label("Personal Identification Numbers (PINs)", systemImage: "key")
        }
        .accessibilityIdentifier("manageCard")
      }
    }
  }
#endif
