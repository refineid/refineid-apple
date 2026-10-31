// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// One row of the Verify screen: the label on the first line, the
  /// value under it, both leading-aligned, and, when the row has an
  /// indicator column, the indicator in a fixed-width trailing column on
  /// the label's first baseline, so every row's indicator sits at the
  /// same trailing edge.
  ///
  /// A row with an indicator column is one accessibility element; a
  /// row without one keeps its texts as their own elements.
  internal struct VerifyDocumentRow<Label: View, Value: View>: View {
    @ScaledMetric(relativeTo: .body)
    private var indicatorWidth = VerifyDocumentRowValue.Indicator.columnWidth

    private let indicator: VerifyDocumentRowValue.Indicator?
    private let label: Label
    private let value: Value

    internal var body: some View {
      if indicator == nil {
        content
      } else {
        content
          .accessibilityElement(children: .combine)
      }
    }

    private var content: some View {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          label
          value
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        if let indicator {
          indicatorView(indicator)
            .frame(width: indicatorWidth)
        }
      }
    }

    /// A row whose `indicator` is nil has no indicator column.
    internal init(
      indicator: VerifyDocumentRowValue.Indicator?,
      @ViewBuilder label: () -> Label,
      @ViewBuilder value: () -> Value
    ) {
      self.indicator = indicator
      self.label = label()
      self.value = value()
    }

    @ViewBuilder
    private func indicatorView(_ indicator: VerifyDocumentRowValue.Indicator) -> some View {
      switch indicator {
      case .progress:
        ProgressView()

      case .hidden, .holds, .fails:
        CredentialValidationIndicator(
          valid: indicator == .holds,
          isEmpty: indicator == .hidden
        )
      }
    }
  }

#endif
