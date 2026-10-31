// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A certificate name as the screen shows it.
internal enum DisplayedSignerName {
  /// `name` with control and format characters (Unicode general
  /// categories Cc and Cf, the bidirectional overrides among them) left
  /// out, so they cannot reorder or hide what is shown.
  internal static func text(of name: String) -> String {
    String(
      String.UnicodeScalarView(
        name.unicodeScalars.filter { scalar in
          switch scalar.properties.generalCategory {
          case .control, .format:
            false

          default:
            true
          }
        }))
  }
}
