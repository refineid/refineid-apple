// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(iOS)
  import UIKit
#endif

#if os(iOS)
  extension CardCredentialsView {
    // MARK: Nested Types

    private enum RemotePairingLayout {
      static let inputSpacing: CGFloat = 8
    }

    // MARK: Computed Properties

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
      if remoteModel.holder != nil {
        return true
      }
      return false
    }

    /// The toggle row.
    internal var remoteAccessToggleRow: some View {
      Toggle(isOn: remoteAccessBinding) {
        HStack(spacing: RemotePairingLayout.inputSpacing) {
          RemotePairingGlyph(
            isConnected: isActivelyConnected
          )
          .frame(width: PersonRowLabel.iconWidth)
          Text(String(localized: "Remote Access"))
        }
      }
      .accessibilityIdentifier("remoteAccessToggle")
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
          // Dismisses the redirect; the switch stays off.
        }
      } message: {
        Text(
          String(
            localized: "Remote Access needs it to let other devices find this iPhone."
          )
        )
      }
    }

    // MARK: Functions

    /// The toggle's binding: the holder's flip reaches the gate first.
    ///
    /// Flipping on opens the education flow instead of enabling
    /// directly; flipping off wipes every remote trace at once.
    private var remoteAccessBinding: Binding<Bool> {
      Binding(
        get: { remoteAccessEnabled },
        set: { setRemoteAccessEnabled($0) }
      )
    }

    private func setRemoteAccessEnabled(_ enabled: Bool) {
      if enabled {
        remoteAccessFlowID = UUID()
        showingLocalNetworkExplainer = true
      } else {
        remoteAccessFlowID = nil
        pairingModel.revokeAll()
        syncRemoteAccessToggle()
      }
    }

    /// Starts serving after the local-network explanation is confirmed.
    private func continueAfterLocalNetworkExplainer() {
      let flow = remoteAccessFlowID
      Task { @MainActor in
        guard flow != nil, flow == remoteAccessFlowID else { return }
        RemoteAccessServing.setEnabled(true)
        syncRemoteAccessToggle()
        let access = await LocalNetworkAccessDetector.currentAccess()
        guard flow == remoteAccessFlowID else { return }
        switch access {
        case .allowed:
          showingNotificationsExplainer = true
        case .denied:
          handleLocalNetworkDenial()
        }
      }
    }

    /// Asks for notifications after their explanation is confirmed.
    private func continueAfterNotificationsExplainer() {
      RappAuthorizationInbox.shared.ensureAuthorization()
    }

    /// Turns remote access back off when the network says no.
    ///
    /// The switch must not claim an access it lacks.
    internal func handleLocalNetworkDenial() {
      guard RemoteAccessGate.isEnabled else { return }
      remoteAccessFlowID = nil
      pairingModel.revokeAll()
      syncRemoteAccessToggle()
      showingLocalNetworkDenied = true
    }

    private func openSystemSettings() {
      if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(settingsURL)
      }
    }

    internal func syncRemoteAccessToggle() {
      let enabled = RemoteAccessGate.isEnabled
      if remoteAccessEnabled != enabled {
        remoteAccessEnabled = enabled
      }
    }
  }
#endif
