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

internal struct RappPairingView: View {
  internal enum Layout {
    internal static let iconSize: CGFloat = 22
    internal static let iconWidth: CGFloat = 28
    internal static let codeFontSize: CGFloat = 34
    internal static let codeTracking: CGFloat = 2
    internal static let cardSpacing: CGFloat = 14
    internal static let statusIconSize: CGFloat = 40
    internal static let contentSpacing: CGFloat = 12
    internal static let codeTopPadding: CGFloat = 4
    internal static let buttonVerticalPadding: CGFloat = 4
    internal static let verticalCardPadding: CGFloat = 8
    internal static let statusVerticalPadding: CGFloat = 16
    internal static let badgeHorizontalPadding: CGFloat = 8
    internal static let badgeVerticalPadding: CGFloat = 4
    internal static let badgeOpacity = 0.15
  }

  @Environment(\.dismiss)
  private var dismiss

  @StateObject private var model = RappPairingModel()
  @State private var remoteAccessEnabled = RemoteAccessGate.isEnabled
  @State private var showingLocalNetworkDenied = false

  #if REFINEID_LOCAL_CARD && os(iOS)
    @ObservedObject private var phoneRelay = PhonePersistentTokenRelay.shared
  #endif

  internal var pairingModel: RappPairingModel {
    model
  }

  internal var isRemoteAccessEnabled: Bool {
    remoteAccessEnabled
  }

  /// What the screen says about serving the card.
  internal var servingState: HolderServingState {
    #if REFINEID_LOCAL_CARD && os(iOS)
      HolderServingState.derive(
        enabled: remoteAccessEnabled,
        paired: !model.pairs.isEmpty,
        halted: phoneRelay.relistenPolicy == .explicitUserActionRequired,
        connected: isActivelyConnected
      )
    #else
      HolderServingState.derive(
        enabled: remoteAccessEnabled, paired: !model.pairs.isEmpty, halted: false,
        connected: isActivelyConnected)
    #endif
  }

  internal var remoteAccessBinding: Binding<Bool> {
    Binding(
      get: { remoteAccessEnabled },
      set: { handleToggleChange($0) }
    )
  }

  internal var isActivelyConnected: Bool {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--mock-remote-connected") {
        return true
      }
    #endif
    #if os(iOS) && REFINEID_LOCAL_CARD
      if SupportedCardTransports.offersNearField {
        return phoneRelay.isPeerConnected
      }
    #endif
    return false
  }

  internal var body: some View {
    Form {
      switchSection
      if remoteAccessEnabled {
        pairingPhaseSection
      }
      pairedDevicesSection
    }
    .navigationTitle(String(localized: "Remote Access"))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      model.refresh()
      remoteAccessEnabled = RemoteAccessGate.isEnabled
      if remoteAccessEnabled, case .idle = model.phase {
        model.createOffer()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: RappPairingModel.pairingsDidChangeNotification
      )
    ) { _ in
      model.refresh()
    }
    .alert(
      String(localized: "Local Network Access Is Off"),
      isPresented: $showingLocalNetworkDenied
    ) {
      Button(String(localized: "Open Settings")) {
        openSystemSettings()
      }
      Button(String(localized: "Cancel"), role: .cancel) {
        remoteAccessEnabled = false
      }
    } message: {
      Text(
        String(
          localized: "Remote Access needs it to let other devices find this iPhone."
        )
      )
    }
  }

  internal func handleToggleChange(_ enabled: Bool) {
    if enabled {
      turnRemoteAccessOn()
    } else {
      remoteAccessEnabled = false
      #if os(iOS)
        RemoteAccessServing.setEnabled(false)
      #endif
      model.revokeAll()
      model.resetAttempt()
    }
  }

  /// Starts serving, then lets the system ask for what it has no answer for.
  private func turnRemoteAccessOn() {
    #if os(iOS)
      RemoteAccessServing.setEnabled(true)
      remoteAccessEnabled = true
      Task { @MainActor in
        switch await RemoteAccessPermissions.localNetworkAccess() {
        case .allowed:
          if case .idle = model.phase {
            model.createOffer()
          }
          await RemoteAccessPermissions.requestNotificationsIfUndecided()

        case .denied:
          remoteAccessEnabled = false
          RemoteAccessServing.setEnabled(false)
          showingLocalNetworkDenied = true
        }
      }
    #else
      remoteAccessEnabled = true
      if case .idle = model.phase {
        model.createOffer()
      }
    #endif
  }

  private func openSystemSettings() {
    #if os(iOS)
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
    #endif
  }
}
