// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import SwiftUI

  /// The development error strip, over the bottom of the content it
  /// modifies, and the list it opens.
  ///
  /// Development builds only, and developer-facing: its text is not
  /// localised. The strip takes taps only where it is drawn, so the
  /// window below it stays usable.
  internal struct DevErrorStrip: ViewModifier {
    // MARK: Nested Types

    /// The strip's measurements.
    private enum Layout {
      static let cornerRadius: CGFloat = 8
      static let lineSpacing: CGFloat = 2
      static let columnSpacing: CGFloat = 6
      static let margin: CGFloat = 8
      static let padding: CGFloat = 8
      static let listMinimumWidth: CGFloat = 520
      static let listMinimumHeight: CGFloat = 320
    }

    /// One error as the strip shows it.
    private struct Line: View {
      let entry: DevErrorLog.Entry

      var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.columnSpacing) {
          Text(entry.date, format: .dateTime.hour().minute().second())
            .monospacedDigit()
            .foregroundStyle(.secondary)
          Text(verbatim: entry.source.rawValue)
            .foregroundStyle(.secondary)
          Text(verbatim: DevErrorStrip.text(of: entry))
            .foregroundStyle(.red)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .font(.caption)
      }
    }

    /// Every recent error, with a way to clear them.
    private struct ErrorList: View {
      @Environment(\.dismiss)
      private var dismiss

      let model: DevErrorStripModel

      var body: some View {
        NavigationStack {
          List(model.entries, id: \.identifier) { entry in
            row(entry)
          }
          .navigationTitle(Text(verbatim: "Errors"))
          .toolbar {
            ToolbarItem(placement: .destructiveAction) {
              Button {
                model.clear()
              } label: {
                Text(verbatim: "Clear")
              }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button {
                dismiss()
              } label: {
                Text(verbatim: "Done")
              }
            }
          }
        }
        #if os(macOS)
          .frame(minWidth: Layout.listMinimumWidth, minHeight: Layout.listMinimumHeight)
        #endif
      }

      private func row(_ entry: DevErrorLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: Layout.lineSpacing) {
          HStack(spacing: Layout.columnSpacing) {
            Text(entry.date, format: .dateTime.hour().minute().second())
              .monospacedDigit()
            Text(verbatim: entry.source.rawValue)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          Text(verbatim: DevErrorStrip.text(of: entry))
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
      }
    }

    // MARK: Static Properties

    /// Names the strip for a UI test that opted in.
    internal static let accessibilityIdentifier = "dev-error-strip"

    // MARK: SwiftUI Properties

    @Bindable private var model = DevErrorStripModel.shared
    @Environment(\.scenePhase)
    private var scenePhase

    // MARK: Computed Properties

    private var strip: some View {
      Button {
        model.isListShown = true
      } label: {
        VStack(alignment: .leading, spacing: Layout.lineSpacing) {
          ForEach(model.stripEntries, id: \.identifier) { entry in
            Line(entry: entry)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
      }
      .buttonStyle(.plain)
      .padding(Layout.margin)
      .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    // MARK: Static Functions

    /// An entry's message, with how many times in a row it came.
    private static func text(of entry: DevErrorLog.Entry) -> String {
      entry.occurrences > 1 ? "\(entry.message) (x\(entry.occurrences))" : entry.message
    }

    // MARK: Functions

    internal func body(content: Content) -> some View {
      content
        .overlay(alignment: .bottom) {
          ZStack {
            if model.isStripShown {
              strip
                .transition(.opacity)
            }
          }
          .animation(.easeInOut, value: model.isStripShown)
        }
        .sheet(isPresented: $model.isListShown) {
          ErrorList(model: model)
        }
        .task { model.start() }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .active else { return }
          model.reload()
        }
    }
  }
#endif
