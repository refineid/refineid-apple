// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// One row of the main screen: an icon column, a title, and whatever
/// the trailing edge carries.
///
/// A long holder name wraps once and then shrinks, so a row keeps its
/// height whatever its title is.
internal struct MenuRow<Icon: View, Trailing: View>: View {
  internal let title: String

  /// The identifier UI tests find the title text by, when one does.
  internal private(set) var titleIdentifier: String?

  private let icon: Icon
  private let trailing: Trailing

  internal var body: some View {
    HStack {
      icon
        .font(.system(size: PersonRowLabel.iconPointSize))
        .symbolRenderingMode(.monochrome)
        .frame(width: PersonRowLabel.iconWidth)
      Text(title)
        .lineLimit(PersonRowLabel.titleLineLimit)
        .minimumScaleFactor(PersonRowLabel.minimumTitleScale)
        .multilineTextAlignment(.leading)
        .accessibilityIdentifier(titleIdentifier ?? "")
      Spacer(minLength: PersonRowLabel.trailingGap)
      trailing
    }
  }

  internal init(
    _ title: String,
    @ViewBuilder icon: () -> Icon,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.icon = icon()
    self.trailing = trailing()
  }

  /// Names the title text for UI tests.
  internal func titleIdentifier(_ identifier: String) -> Self {
    var row = self
    row.titleIdentifier = identifier
    return row
  }
}

extension MenuRow where Trailing == EmptyView {
  internal init(_ title: String, @ViewBuilder icon: () -> Icon) {
    self.init(title, icon: icon) {
      EmptyView()
    }
  }
}

extension MenuRow where Icon == MenuSymbol {
  internal init(
    _ title: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.init(title, icon: { MenuSymbol(systemName: systemImage, tint: tint) }, trailing: trailing)
  }
}

extension MenuRow where Icon == MenuSymbol, Trailing == EmptyView {
  internal init(_ title: String, systemImage: String, tint: Color) {
    self.init(title, systemImage: systemImage, tint: tint) {
      EmptyView()
    }
  }
}
