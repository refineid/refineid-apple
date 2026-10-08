// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// A section header flush with its rows.
internal struct CompactSectionHeader: View {
  internal let title: String

  internal var body: some View {
    Text(title)
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowInsets(EdgeInsets())
  }
}
