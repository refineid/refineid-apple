// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The Time Stamp pane: the one service signatures ask.
  ///
  /// The address is stored as typed; the store answers the shipped
  /// service until what is typed names a usable one, so a half-typed
  /// address never breaks signing.
  internal struct TimestampAuthoritySettingsView: View {
    @State private var address = TimestampAuthorityStore.load(from: .standard)

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
              address = TimestampAuthorityStore.defaultAuthority
            }
            .disabled(address == TimestampAuthorityStore.defaultAuthority)
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
