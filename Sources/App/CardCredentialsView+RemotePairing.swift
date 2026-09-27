// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(iOS)
  extension CardCredentialsView {
    // MARK: Nested Types

    private enum RemotePairingLayout {
      static let inputSpacing: CGFloat = 8
      static let tapTargetSide: CGFloat = 44
      static let forgetButtonGap: CGFloat = 4
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

    private var isActivelyConnected: Bool {
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

    /// The holder's Remote Access section: one toggle and the pairing it guards.
    ///
    /// Remote serving is opt-in and off by default. The toggle records the
    /// choice; entering a valid pairing code or tapping Disconnect flips it
    /// the same way, so the switch always shows what the radios are doing.
    internal var remoteAccessSection: some View {
      Section {
        remoteAccessToggleRow
        remotePairingControlsRow
      } header: {
        compactSectionHeader("Remote Access")
      } footer: {
        Text(
          String(localized: "When on, your Mac or PC finds this iPhone on the local network.")
        )
        Text(
          String(localized: "Pair with the 6-digit code shown on your computer.")
        )
      }
      .onAppear {
        syncRemoteAccessToggle()
        pairingModel.refresh()
        RappAutoPairingService.shared.reconcile()
        #if os(iOS) && REFINEID_LOCAL_CARD
          phoneRelay.updatePeerOnlineState()
        #endif
      }
      .onReceive(pairingModel.$phase) { _ in
        syncRemoteAccessToggle()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappPairingModel.pairingsDidChangeNotification)
      ) { _ in
        pairingModel.refresh()
        syncRemoteAccessToggle()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappAutoPairingService.pairingsDidChangeNotification)
      ) { _ in
        pairingModel.refresh()
        #if os(iOS) && REFINEID_LOCAL_CARD
          phoneRelay.updatePeerOnlineState()
        #endif
        syncRemoteAccessToggle()
      }
    }

    private var remoteAccessToggleRow: some View {
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
    }

    @ViewBuilder private var remotePairingControlsRow: some View {
      if isPairingInputActive {
        inlinePairingControls
      } else if pairingModel.hasActivePairs {
        HStack(spacing: RemotePairingLayout.forgetButtonGap) {
          connectedStatusChip
          Spacer()
          disconnectButton
        }
      } else {
        HStack {
          Spacer()
          Button(String(localized: "Connect")) {
            togglePairingInput()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier("remoteConnectButton")
        }
      }
    }

    private var disconnectButton: some View {
      Button(role: .destructive) {
        withAnimation {
          isPairingInputActive = false
          pairingCodeDigits = ""
          isPairingFieldFocused = false
          pairingModel.revokeAll()
          syncRemoteAccessToggle()
        }
      } label: {
        Image(systemName: "minus.circle")
          .font(.title3)
          .foregroundStyle(.red)
      }
      .buttonStyle(.borderless)
      .frame(
        width: RemotePairingLayout.tapTargetSide,
        height: RemotePairingLayout.tapTargetSide
      )
      .contentShape(Rectangle())
      .accessibilityLabel(Text("Disconnect"))
      .accessibilityIdentifier("remoteDisconnectButton")
    }

    private var statusChipTitle: String {
      if !remoteAccessEnabled {
        String(localized: "Off")
      } else if isActivelyConnected {
        String(localized: "Connected")
      } else {
        String(localized: "Offline")
      }
    }

    private var connectedStatusChip: some View {
      Button(statusChipTitle) {
        retryRemoteConnection()
      }
      .buttonStyle(.bordered)
      .tint(remoteAccessEnabled && isActivelyConnected ? .green : .secondary)
      .controlSize(.small)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .allowsHitTesting(!isActivelyConnected || !remoteAccessEnabled)
    }

    @ViewBuilder private var inlinePairingControls: some View {
      HStack(spacing: RemotePairingLayout.inputSpacing) {
        pairingCodeDisplay
          .overlay {
            TextField("", text: pairingCodeBinding)
              .textFieldStyle(.plain)
              .keyboardType(.numberPad)
              .textInputAutocapitalization(.never)
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
          prompt: "123",
          showsCaret: isPairingFieldFocused
            && pairingCodeDigits.count < RappPairingCode.groupSize
        )
        Text(verbatim: " ")
        pairingGroupLabel(
          digits: String(pairingCodeDigits.dropFirst(RappPairingCode.groupSize)),
          prompt: "456",
          showsCaret: isPairingFieldFocused
            && pairingCodeDigits.count >= RappPairingCode.groupSize
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
    /// The gate leads so a sync landing mid-flip converges instead of
    /// reverting: it can only ever read the choice just made. Syncs from
    /// pairing and notification observers flow the other way, into the
    /// switch, and never touch the radios themselves.
    private var remoteAccessBinding: Binding<Bool> {
      Binding(
        get: { remoteAccessEnabled },
        set: { setRemoteAccessEnabled($0) }
      )
    }

    private func setRemoteAccessEnabled(_ enabled: Bool) {
      RemoteAccessServing.setEnabled(enabled)
      if !enabled {
        isPairingInputActive = false
        pairingCodeDigits = ""
        isPairingFieldFocused = false
        pairingModel.cancel()
      }
      syncRemoteAccessToggle()
    }

    private func retryRemoteConnection() {
      if !remoteAccessEnabled {
        setRemoteAccessEnabled(true)
        return
      }
      #if os(iOS) && REFINEID_LOCAL_CARD
        if !isActivelyConnected {
          phoneRelay.resumeAfterUserAction()
          RappAutoPairingService.shared.reconcile()
        }
      #endif
    }

    private func syncRemoteAccessToggle() {
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

    private func togglePairingInput() {
      withAnimation {
        if isPairingInputActive {
          isPairingInputActive = false
          pairingModel.cancel()
          pairingCodeDigits = ""
          isPairingFieldFocused = false
        } else {
          isPairingInputActive = true
          pairingModel.startCodeEntry()
          pairingCodeDigits = ""
          isPairingFieldFocused = true
        }
      }
    }
  }
#endif
