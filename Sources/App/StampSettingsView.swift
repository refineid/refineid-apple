// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_PDF_STAMP

  import SwiftUI

  /// The Stamp pane: whether signed PDFs receive a visible stamp.
  internal struct StampSettingsView: View {
    @State private var isStampEnabled = StampStore.isEnabled()

    internal var body: some View {
      Form {
        Toggle(
          String(localized: "Add a stamp to the PDF file"),
          isOn: $isStampEnabled
        )
        .accessibilityIdentifier("stampEnabledToggle")
        .onChange(of: isStampEnabled) { _, newValue in
          StampStore.setEnabled(newValue)
        }
      }
      .formStyle(.grouped)
    }
  }

#endif
