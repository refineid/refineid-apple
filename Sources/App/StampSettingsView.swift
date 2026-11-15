// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_PDF_STAMP

  import SwiftUI

  /// The Stamp pane: whether signed PDFs receive a visible stamp.
  internal struct StampSettingsView: View {
    @State private var isStampEnabled = StampStore.isEnabled()

    private var footerView: some View {
      Text(
        String(
          localized: """
            Adds a visible stamp to the bottom of the signed PDF document \
            advising verification of the electronic signature.
            """
        )
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }

    internal var body: some View {
      Form {
        Section {
          Toggle(String(localized: "Stamp"), isOn: $isStampEnabled)
            .accessibilityIdentifier("stampEnabledToggle")
            .onChange(of: isStampEnabled) { _, newValue in
              StampStore.setEnabled(newValue)
            }
        } footer: {
          footerView
        }
      }
      .formStyle(.grouped)
    }
  }

#endif
