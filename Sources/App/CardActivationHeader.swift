// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The activation form's title above its first group's header, the
/// activation code.
internal struct CardActivationHeader: View {
  /// The gap between the title and the group's header.
  private static let titleSpacing: CGFloat = 12

  internal var body: some View {
    VStack(alignment: .leading, spacing: Self.titleSpacing) {
      Text("Identity card activation")
        .font(.title3.bold())
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)
      Text("Activation PIN")
    }
  }
}
