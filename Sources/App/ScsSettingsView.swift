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

        if let statusError = service.statusError {
          Text(statusError)
            .foregroundStyle(.red)
            .accessibilityIdentifier("scsStatusError")
        }

        if let pendingOrigin = service.pendingRequestOrigin {
          Text(
            String(
              localized: "Signature request waiting for approval: \(pendingOrigin)"
            )
          )
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("scsPendingRequest")
        }

        if let holderNotice = service.holderNotice {
          Text(holderNotice)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("scsHolderNotice")
        }
      }
      .formStyle(.grouped)
    }
  }
#endif
