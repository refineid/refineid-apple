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
      static let identityDetailsSpacing: CGFloat = 4
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

    @ViewBuilder internal var remoteRouteRow: some View {
      HStack(spacing: RemotePairingLayout.inputSpacing) {
        Group {
          if remoteCardAvailable {
            RemotePairingGlyph(
              isConnected: isActivelyConnected
            )
          } else {
            PersonRowLabel.cardIcon(
              systemName: "key.radiowaves.forward",
              lit: false
            )
          }
        }
        .frame(width: PersonRowLabel.iconWidth)
        Text(String(localized: "Remote Access"))
          .foregroundStyle(
            remoteCardAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
          )
          .accessibilityIdentifier("remoteCard")
        Spacer()
        if remoteCardAvailable {
          remoteRouteTrailingControls
        }
      }
      .buttonStyle(.borderless)
      .disabled(!remoteCardAvailable)
      .onAppear {
        pairingModel.refresh()
        RappAutoPairingService.shared.reconcile()
        #if os(iOS) && REFINEID_LOCAL_CARD
          phoneRelay.resumeServing()
          phoneRelay.updatePeerOnlineState()
        #endif
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappPairingModel.pairingsDidChangeNotification)
      ) { _ in
        pairingModel.refresh()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappAutoPairingService.pairingsDidChangeNotification)
      ) { _ in
        pairingModel.refresh()
        #if os(iOS) && REFINEID_LOCAL_CARD
          phoneRelay.updatePeerOnlineState()
        #endif
      }
    }

    @ViewBuilder private var remoteRouteTrailingControls: some View {
      if isPairingInputActive {
        inlinePairingControls
      } else if pairingModel.hasActivePairs {
        HStack(spacing: RemotePairingLayout.forgetButtonGap) {
          connectedStatusChip
          Button(role: .destructive) {
            withAnimation {
              pairingModel.revokeAll()
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
      } else {
        Button(String(localized: "Connect")) {
          togglePairingInput()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("remoteConnectButton")
      }
    }

    private var connectedStatusChip: some View {
      Button(isActivelyConnected ? String(localized: "Connected") : String(localized: "Offline")) {
        #if os(iOS) && REFINEID_LOCAL_CARD
          if !isActivelyConnected {
            phoneRelay.resumeAfterUserAction()
            RappAutoPairingService.shared.reconcile()
          }
        #endif
      }
      .buttonStyle(.bordered)
      .tint(isActivelyConnected ? .green : .secondary)
      .controlSize(.small)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .allowsHitTesting(!isActivelyConnected)
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

    @ViewBuilder private var remoteActionContent: some View {
      if case .offer(let code) = pairingModel.phase {
        Text(RappPairingCode.formatted(code))
          .font(.body.monospacedDigit().weight(.semibold))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.trailing)
          .accessibilityIdentifier("pairingCode")
      } else if case .connecting = pairingModel.phase {
        ProgressView()
          .controlSize(.small)
      } else {
        Button(String(localized: "Connect")) {
          withAnimation {
            pairingModel.createOffer()
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("connectRemoteReader")
      }
    }

    @ViewBuilder private var remoteIdentityRow: some View {
      if case .identity(let holder) = remoteModel.phase,
        PersistentTokenRegistry.shared.holderLine != nil
      {
        HStack {
          VStack(alignment: .leading, spacing: RemotePairingLayout.identityDetailsSpacing) {
            PersonRowLabel(configured: true)
            Text(holder)
              .font(.body)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .accessibilityIdentifier("remoteCardHolder")
          }
          Spacer(minLength: RemotePairingLayout.forgetButtonGap)
          Button(role: .destructive) {
            withAnimation {
              pairingModel.cancel()
              remoteModel.forget()
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
          .accessibilityLabel(Text("Forget identity"))
          .accessibilityIdentifier("forgetRemoteIdentity")
        }
      } else {
        LabeledContent {
          remoteActionContent
        } label: {
          PersonRowLabel(configured: false)
        }
      }
    }

    internal var remoteReaderSection: some View {
      Section {
        remoteIdentityRow
        if remoteModel.phase == .failed {
          Text(remoteModel.failureText ?? String(localized: "The remote card could not be read."))
            .foregroundStyle(.secondary)
        }
      } header: {
        compactSectionHeader("Identity")
      }
      .onValueChange(of: remoteModel.needsFreshPairing) { needsFresh in
        if needsFresh {
          remoteModel.acknowledgeFreshPairing()
          pairingModel.createOffer()
        }
      }
      .onReceive(pairingModel.$phase) { phase in
        if case .paired = phase {
          remoteModel.refreshThenConnect()
        }
      }
    }

    // MARK: Functions

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
#else
  extension CardCredentialsView {
    internal var remoteReaderSection: some View {
      EmptyView()
    }
  }
#endif
