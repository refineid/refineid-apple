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
          return phoneRelay.isPeerConnected
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
    /// Flipping on starts serving and lets the system ask for what it
    /// has no answer for; flipping off wipes every remote trace at once.
    private var remoteAccessBinding: Binding<Bool> {
      Binding(
        get: { remoteAccessEnabled },
        set: { setRemoteAccessEnabled($0) }
      )
    }

    private func setRemoteAccessEnabled(_ enabled: Bool) {
      if enabled {
        let flow = UUID()
        remoteAccessFlowID = flow
        turnRemoteAccessOn(flow: flow)
      } else {
        remoteAccessFlowID = nil
        pairingModel.revokeAll()
        syncRemoteAccessToggle()
      }
    }

    private func turnRemoteAccessOn(flow: UUID) {
      Task { @MainActor in
        guard flow == remoteAccessFlowID else { return }
        RemoteAccessServing.setEnabled(true)
        syncRemoteAccessToggle()
        let access = await RemoteAccessPermissions.localNetworkAccess()
        guard flow == remoteAccessFlowID else { return }
        switch access {
        case .allowed:
          await RemoteAccessPermissions.requestNotificationsIfUndecided()

        case .denied:
          handleLocalNetworkDenial()
        }
      }
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
      RemoteAccessPermissions.openSettings()
    }

    internal func syncRemoteAccessToggle() {
      let enabled = RemoteAccessGate.isEnabled
      if remoteAccessEnabled != enabled {
        remoteAccessEnabled = enabled
      }
    }
  }
#endif
