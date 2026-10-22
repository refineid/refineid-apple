// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The key beside the local card's line: it opens the PIN codes window.
  internal struct PinCodesButton: View {
    @Environment(\.openWindow)
    private var openWindow

    internal var body: some View {
      Button {
        openWindow(id: PinCodesWindow.windowID)
      } label: {
        Image(systemName: "key")
      }
      .buttonStyle(.borderless)
      .help(Text("PIN Codes"))
      .accessibilityLabel(Text("PIN Codes"))
      .accessibilityIdentifier("manageCard")
    }
  }

#endif
