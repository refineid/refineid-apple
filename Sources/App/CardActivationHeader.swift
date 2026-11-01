// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The activation form's title above its first group's header, the
/// activation code.
internal struct CardActivationHeader: View {
  /// The gap between the title and the group's header, wide enough that
  /// the title reads as the window's and not the group's.
  private static let titleSpacing: CGFloat = 28

  internal var body: some View {
    VStack(alignment: .leading, spacing: Self.titleSpacing) {
      Text("Identity card activation")
        .font(.largeTitle.bold())
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)
      Text("Activation PIN")
        .accessibilityAddTraits(.isHeader)
    }
  }
}
