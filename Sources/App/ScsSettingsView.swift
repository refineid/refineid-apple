// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import SwiftUI

  internal struct ScsSettingsView: View {
    @ObservedObject private var service = ScsService.shared

    internal var body: some View {
      Form {
        Toggle(
          String(localized: "Signature Creation Service"),
          isOn: Binding(
            get: { service.isEnabled },
            set: { service.setEnabled($0) }
          )
        )
        .accessibilityIdentifier("scsEnabled")
      }
      .formStyle(.grouped)
    }
  }
#endif
