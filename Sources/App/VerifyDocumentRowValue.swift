// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// The trailing value of one verification fact row: optional text,
  /// then the indicator, whose space is kept when the row shows none,
  /// so every row's indicator sits in the same trailing column.
  internal struct VerifyDocumentRowValue: View {
    /// What the indicator column shows.
    internal enum Indicator {
      /// No indicator; its space is kept.
      case hidden

      /// The fact holds.
      case holds

      /// The fact fails.
      case fails
    }

    internal var text: String?
    internal var secondaryText: String?
    internal var progress = false
    internal var indicator = Indicator.hidden

    internal var body: some View {
      HStack {
        if progress {
          ProgressView()
        }
        if let text {
          Text(text)
            .multilineTextAlignment(.trailing)
        }
        if let secondaryText {
          Text(secondaryText)
            .foregroundStyle(.secondary)
        }
        CredentialValidationIndicator(
          valid: indicator == .holds,
          isEmpty: indicator == .hidden
        )
      }
    }
  }

#endif
