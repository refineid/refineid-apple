// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import SwiftUI

  /// Every recent error in full, newest first, with ways to copy and
  /// clear them.
  ///
  /// Development builds only, and developer-facing: its text is not
  /// localised.
  internal struct DevErrorList: View {
    // MARK: Nested Types

    /// One error in full: when, from where, and the whole message,
    /// wrapped and selectable.
    internal struct Row: View {
      /// The error shown.
      internal let entry: DevErrorLog.Entry

      internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.lineSpacing) {
          HStack(spacing: Layout.columnSpacing) {
            Text(entry.date, format: .dateTime.hour().minute().second())
              .monospacedDigit()
            Text(verbatim: entry.source.rawValue)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          Text(verbatim: entry.text)
            .font(.callout)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }
    }

    /// The list's measurements.
    private enum Layout {
      static let lineSpacing: CGFloat = 2
      static let columnSpacing: CGFloat = 6
      static let padding: CGFloat = 10
    }

    // MARK: Static Properties

    /// Names the list for a UI test that opted in.
    internal static let accessibilityIdentifier = "dev-error-list"

    /// Seconds the copy button says it copied: long enough to notice,
    /// short enough not to go stale.
    private static let copiedFeedbackSeconds = 2

    // MARK: Properties

    /// The errors shown.
    internal let model: DevErrorModel

    // MARK: SwiftUI Properties

    @Environment(\.dismiss)
    private var dismiss
    @State private var isCopied = false

    // MARK: Computed Properties

    internal var body: some View {
      VStack(spacing: 0) {
        actions
        Divider()
        if model.entries.isEmpty {
          Text(verbatim: "No errors")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(model.entries, id: \.identifier) { entry in
            Row(entry: entry)
          }
          .listStyle(.plain)
        }
      }
      .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    private var actions: some View {
      HStack {
        Text(verbatim: "Errors (\(model.entries.count))")
          .font(.headline)
        Spacer()
        Button {
          copyAll()
        } label: {
          Text(verbatim: isCopied ? "Copied" : "Copy All")
        }
        .disabled(model.entries.isEmpty)
        Button(role: .destructive) {
          model.clear()
        } label: {
          Text(verbatim: "Clear")
        }
        .disabled(model.entries.isEmpty)
        #if os(iOS)
          Button {
            dismiss()
          } label: {
            Text(verbatim: "Done")
              .bold()
          }
        #endif
      }
      .padding(Layout.padding)
    }

    // MARK: Functions

    private func copyAll() {
      DiagnosticsClipboard.copy(model.transcript)
      isCopied = true
      Task {
        try? await Task.sleep(for: .seconds(Self.copiedFeedbackSeconds))
        isCopied = false
      }
    }
  }
#endif
