// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The person row label carrying its configuration-state icon.
internal struct PersonRowLabel: View {
  /// The fixed icon column keeps row titles aligned across icons of
  /// different widths.
  internal static let iconWidth: CGFloat = 36

  /// Point size every Card-row symbol uses, including Remote.
  internal static let iconPointSize: CGFloat = 28

  /// A row title wraps once, then shrinks this far before truncating.
  internal static let titleLineLimit = 2
  internal static let minimumTitleScale: CGFloat = 0.85

  /// Between a row title and whatever trails it.
  internal static let trailingGap: CGFloat = 4

  /// Whether an identity is configured behind the row.
  internal let configured: Bool

  internal var body: some View {
    HStack {
      Image(
        systemName: configured
          ? "person.fill.checkmark"
          : "person.fill.questionmark"
      )
      .font(.system(size: Self.iconPointSize))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(Color.accentColor)
      .frame(width: Self.iconWidth)
      .accessibilityHidden(true)
      Text("Person")
    }
  }

  /// One Card-row symbol, monochrome so inactive grey matches.
  internal static func cardIcon(systemName: String, lit: Bool) -> some View {
    Image(systemName: systemName)
      .font(.system(size: iconPointSize))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(lit ? Color.accentColor : Color.secondary)
      .frame(width: iconWidth)
      .accessibilityHidden(true)
  }
}
