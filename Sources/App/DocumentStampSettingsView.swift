// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// Explains the visible mark placed on signed PDFs.
  internal struct DocumentStampSettingsView: View {
    private static let paneWidth: CGFloat = 520
    private static let paneHeight: CGFloat = 170

    internal var body: some View {
      Form {
        Section {
          Text(
            "The visual PDF stamp advises examining the document's electronic signature container "
              + "rather than relying on visible ink on the page. "
              + "It carries no personal names, identifiers, or handwritten signatures."
          )
          .font(.body)
          .foregroundStyle(.secondary)
        } header: {
          Text("Visible PDF Stamp")
        }
      }
      .formStyle(.grouped)
      .frame(minWidth: Self.paneWidth, minHeight: Self.paneHeight)
    }
  }

#endif
