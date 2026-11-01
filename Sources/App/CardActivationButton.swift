// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The activation form's one action: full width and large on iPhone and
/// iPad, centred under the last group on the Mac.
internal struct CardActivationButton: View {
  internal let enabled: Bool
  internal let action: () -> Void

  internal var body: some View {
    Button(action: action) {
      Text("Activate Card")
        #if os(iOS)
          .frame(maxWidth: .infinity)
        #endif
    }
    .buttonStyle(.borderedProminent)
    #if os(iOS)
      .controlSize(.large)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    #else
      .frame(maxWidth: .infinity)
    #endif
    .keyboardShortcut(.defaultAction)
    .disabled(!enabled)
    .accessibilityIdentifier("managementActivate")
  }
}
