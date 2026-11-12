// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_TIMESTAMP_CONFIG

  import SwiftUI

  /// The Time Stamp pane: the one service signatures ask.
  ///
  /// The address is stored as typed; the store answers the shipped
  /// service until what is typed names a usable one, so a half-typed
  /// address never breaks signing. The field opens on the stored
  /// draft, not the effective service, so a half-typed address is
  /// still visible after a relaunch.
  internal struct TimestampAuthoritySettingsView: View {
    @State private var address =
      TimestampAuthorityStore.configured(in: .standard)
      ?? TimestampAuthorityStore.defaultAddress

    internal var body: some View {
      Form {
        Section {
          TextField(String(localized: "Address"), text: $address)
            .accessibilityIdentifier("timestampAuthorityField")
            .onChange(of: address) { _, typed in
              TimestampAuthorityStore.store(typed, in: .standard)
            }
          HStack {
            Spacer()
            Button(String(localized: "Restore Defaults")) {
              TimestampAuthorityStore.restoreDefaults(in: .standard)
              address = TimestampAuthorityStore.defaultAddress
            }
            .disabled(address == TimestampAuthorityStore.defaultAddress)
          }
        } footer: {
          if !TimestampAuthorityStore.isUsable(address) {
            Label(
              String(localized: "Not a usable address"),
              systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .font(.footnote)
          }
        }
      }
      .formStyle(.grouped)
    }
  }

#endif
