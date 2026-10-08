// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// A decorative system symbol in a menu row's icon column.
internal struct MenuSymbol: View {
  internal let systemName: String
  internal let tint: Color

  internal var body: some View {
    Image(systemName: systemName)
      .foregroundStyle(tint)
      .accessibilityHidden(true)
  }
}
