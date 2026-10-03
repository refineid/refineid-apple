// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The identity navigation row on the main screen that opens the identity submenu.
internal struct CardIdentitySection: View {
  private static let minHolderScale: CGFloat = 0.85
  private static let holderLineLimit: Int = 2
  private static let rowSpacing: CGFloat = 4

  /// The complete holder name read from the primed identity certificate.
  internal let holder: String

  /// Action executed when the identity row is tapped.
  internal let onSelect: (() -> Void)?

  private var rowContent: some View {
    HStack {
      Image(systemName: "person")
        .font(.system(size: PersonRowLabel.iconPointSize))
        .symbolRenderingMode(.monochrome)
        .frame(width: PersonRowLabel.iconWidth)
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
      Text(holder)
        .font(.body)
        .foregroundStyle(.primary)
        .lineLimit(Self.holderLineLimit)
        .minimumScaleFactor(Self.minHolderScale)
        .multilineTextAlignment(.leading)
        .accessibilityIdentifier("identityStatus")
      Spacer(minLength: Self.rowSpacing)
      #if os(iOS)
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      #endif
    }
  }

  internal var body: some View {
    Section {
      #if os(iOS)
        Button {
          onSelect?()
        } label: {
          rowContent
        }
        .tint(.primary)
        .accessibilityIdentifier("identitySubmenuButton")
      #else
        rowContent
      #endif
    } header: {
      Text(String(localized: "Identity"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
    }
  }

  internal init(holder: String) {
    self.holder = holder
    self.onSelect = nil
  }

  internal init(holder: String, onSelect: @escaping () -> Void) {
    self.holder = holder
    self.onSelect = onSelect
  }
}
