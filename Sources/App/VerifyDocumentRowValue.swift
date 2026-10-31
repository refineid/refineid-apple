// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// What one verification fact row shows: an optional value text,
  /// optional secondary text after it, and the indicator.
  internal struct VerifyDocumentRowValue {
    /// What the indicator column shows.
    internal enum Indicator {
      /// No indicator; the column keeps its space.
      case hidden

      /// The fact is being established.
      case progress

      /// The fact holds.
      case holds

      /// The fact fails.
      case fails

      /// Width of the trailing indicator column at the default text size.
      internal static let columnWidth: CGFloat = 28
    }

    internal var text: String?
    internal var secondaryText: String?
    internal var indicator = Indicator.hidden

    /// The value line as VoiceOver reads it: the text and the
    /// secondary text separated by a pause.
    internal var accessibilityLine: String {
      [text, secondaryText].compactMap(\.self).joined(separator: ", ")
    }

    /// The value line: the text, then the secondary text in the
    /// secondary style, or nil when the row has neither.
    internal var line: AttributedString? {
      var secondary = secondaryText.map { AttributedString($0) }
      secondary?.foregroundColor = .secondary
      switch (text.map { AttributedString($0) }, secondary) {
      case (let primary?, let secondary?):
        return primary + AttributedString(" ") + secondary

      case (let primary?, nil):
        return primary

      case (nil, let secondary?):
        return secondary

      case (nil, nil):
        return nil
      }
    }
  }

#endif
