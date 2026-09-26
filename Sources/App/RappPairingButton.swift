// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

internal struct RappPairingButton: View {
  @Binding internal var isPresented: Bool
  @State private var hasSelectedPair = false

  private var isConnected: Bool {
    hasSelectedPair || PersistentTokenRegistry.shared.holderLine != nil
  }

  internal var body: some View {
    Button {
      isPresented = true
    } label: {
      RemotePairingGlyph(isConnected: isConnected)
    }
    .accessibilityLabel(String(localized: "Remote Access"))
    .accessibilityValue(
      isConnected ? "Paired device selected" : "No paired device selected"
    )
    .task(id: isPresented) {
      await refreshSelection()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: RappPairingModel.pairingsDidChangeNotification)
    ) { _ in
      Task { await refreshSelection() }
    }
  }

  /// Re-reads whether a requester pairing is still selected.
  private func refreshSelection() async {
    let catalog = RappPairCatalog(vault: RappDeviceVault())
    hasSelectedPair = (try? await catalog.selectedPair()) != nil
  }
}
