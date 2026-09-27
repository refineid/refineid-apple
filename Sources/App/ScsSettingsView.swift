// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import SwiftUI

  internal struct ScsSettingsView: View {
    @ObservedObject private var service = ScsService.shared

    internal var body: some View {
      Form {
        Section {
          Toggle(
            String(localized: "Enable local web signing (SCS)"),
            isOn: Binding(
              get: { service.isEnabled },
              set: { service.setEnabled($0) }
            )
          )
          .accessibilityIdentifier("scsEnabled")
        } footer: {
          Text(
            """
            Allows websites to request card signatures through this Mac. Disabled by default. \
            Enabling starts a local HTTPS server at 127.0.0.1:53952 and may ask you to trust its \
            certificate in a system dialog. Each signature requires your approval. Turning this \
            off closes the server and its connections; it does not remove existing certificate trust.
            """
          )
        }
      }
      .formStyle(.grouped)
    }
  }
#endif
