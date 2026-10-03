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
      static let caretWidth: CGFloat = 2
      static let caretVerticalInset: CGFloat = 2
      static let spinnerSlotSide: CGFloat = 20
    }

    // MARK: Computed Properties

    private var pairingCodeBinding: Binding<String> {
      Binding(
        get: { pairingCodeDigits },
        set: { applyPairingDigits($0) }
      )
    }

    private var pairingGroupFont: Font {
      .body.monospacedDigit().weight(.semibold)
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
      if remoteModel.holder != nil {
        return true
      }
      return false
    }

    /// The toggle row; the code boxes join it below while unpaired.
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

    /// The pairing-code boxes, shown while on and unpaired.
    @ViewBuilder internal var remotePairingCodeRow: some View {
      if remoteAccessEnabled, !pairingModel.hasActivePairs {
        inlinePairingControls
          .onAppear {
            if shouldFocusPairingEntry {
              shouldFocusPairingEntry = false
              isPairingFieldFocused = true
            }
          }
      }
    }

    @ViewBuilder private var inlinePairingControls: some View {
      HStack(spacing: RemotePairingLayout.inputSpacing) {
        pairingCodeDisplay
          .overlay {
            TextField("", text: pairingCodeBinding)
              .textFieldStyle(.plain)
              #if os(iOS)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
              #endif
              .autocorrectionDisabled()
              .focused($isPairingFieldFocused)
              .foregroundStyle(.clear)
              .tint(.clear)
              .accessibilityIdentifier("pairingCodeEntry")
          }
        ZStack {
          if case .connecting = pairingModel.phase {
            ProgressView()
              .controlSize(.small)
          }
        }
        .frame(
          width: RemotePairingLayout.spinnerSlotSide,
          height: RemotePairingLayout.spinnerSlotSide
        )
      }
    }

    private var pairingCodeDisplay: some View {
      HStack(spacing: 0) {
        pairingGroupLabel(
          digits: String(pairingCodeDigits.prefix(RappPairingCode.groupSize)),
          prompt: "7K",
          showsCaret: isPairingFieldFocused
            && pairingCodeDigits.count < RappPairingCode.groupSize
        )
        Text(verbatim: " ")
        pairingGroupLabel(
          digits: String(
            pairingCodeDigits.dropFirst(RappPairingCode.groupSize).prefix(RappPairingCode.groupSize)
          ),
          prompt: "X4",
          showsCaret: isPairingFieldFocused
            && pairingCodeDigits.count >= RappPairingCode.groupSize
            && pairingCodeDigits.count < RappPairingCode.doubleGroupSize
        )
        Text(verbatim: " ")
        pairingGroupLabel(
          digits: String(pairingCodeDigits.dropFirst(RappPairingCode.doubleGroupSize)),
          prompt: "M9",
          showsCaret: isPairingFieldFocused
            && pairingCodeDigits.count >= RappPairingCode.doubleGroupSize
            && pairingCodeDigits.count < RappPairingCode.codeLength
        )
      }
      .font(pairingGroupFont)
      .fixedSize(horizontal: true, vertical: false)
      .accessibilityHidden(true)
    }

    private var pairingCaret: some View {
      Rectangle()
        .fill(Color.accentColor)
        .frame(width: RemotePairingLayout.caretWidth)
        .padding(.vertical, RemotePairingLayout.caretVerticalInset)
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
        pairingCodeDigits = ""
        isPairingFieldFocused = false
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
      shouldFocusPairingEntry = true
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

    private func pairingGroupLabel(
      digits: String,
      prompt: String,
      showsCaret: Bool
    ) -> some View {
      Text(verbatim: String(repeating: "0", count: RappPairingCode.groupSize))
        .hidden()
        .overlay(alignment: .leading) {
          ZStack(alignment: .leading) {
            if digits.isEmpty {
              Text(prompt)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
              Text(digits)
                .foregroundStyle(.primary)
              if showsCaret {
                pairingCaret
              }
              Spacer(minLength: 0)
            }
          }
        }
    }

    private func applyPairingDigits(_ digits: String) {
      let normalized = RappPairingCode.normalize(digits)
      pairingCodeDigits = normalized
      if RappPairingCode.isValid(normalized) {
        isPairingFieldFocused = false
        pairingModel.acceptPairingCode(normalized)
      } else if pairingModel.phase != .codeEntry {
        pairingModel.startCodeEntry()
      }
    }
  }
#endif
