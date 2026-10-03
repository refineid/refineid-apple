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
    internal static let textLineSpacing: CGFloat = 2
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
  @State private var showingLocalNetworkExplainer = false
  @State private var showingNotificationsExplainer = false
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
        return phoneRelay.isPeerConnectedOrOnline
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
      String(localized: "Remote Card Use"),
      isPresented: $showingLocalNetworkExplainer
    ) {
      Button(String(localized: "OK")) {
        continueAfterLocalNetworkExplainer()
      }
    } message: {
      Text(String(localized: "Network access is required."))
    }
    .alert(
      String(localized: "Allow Notifications"),
      isPresented: $showingNotificationsExplainer
    ) {
      Button(String(localized: "OK")) {
        continueAfterNotificationsExplainer()
      }
    } message: {
      Text(
        String(
          localized:
            "Get notified when a nearby device needs this iPhone; without it, Remote Access works only while open."
        )
      )
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
      showingLocalNetworkExplainer = true
    } else {
      remoteAccessEnabled = false
      #if os(iOS)
        RemoteAccessServing.setEnabled(false)
      #endif
      model.revokeAll()
      model.resetAttempt()
    }
  }

  private func continueAfterLocalNetworkExplainer() {
    #if os(iOS)
      RemoteAccessServing.setEnabled(true)
      remoteAccessEnabled = true
      Task { @MainActor in
        let access = await LocalNetworkAccessDetector.currentAccess()
        switch access {
        case .allowed:
          showingNotificationsExplainer = true
          if case .idle = model.phase {
            model.createOffer()
          }
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

  private func continueAfterNotificationsExplainer() {
    #if os(iOS)
      RappAuthorizationInbox.shared.ensureAuthorization()
    #endif
    if case .idle = model.phase {
      model.createOffer()
    }
  }

  private func openSystemSettings() {
    #if os(iOS)
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
    #endif
  }
}
