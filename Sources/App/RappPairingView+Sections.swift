// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import RappEngine
import SwiftUI

extension RappPairingView {
  // MARK: - Properties

  internal var switchSection: some View {
    Section {
      HStack(spacing: Layout.contentSpacing) {
        Image(systemName: "antenna.radiowaves.left.and.right")
          .font(.system(size: Layout.iconSize))
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(
            isActivelyConnected
              ? Color.green
              : (isRemoteAccessEnabled ? Color.accentColor : Color.secondary)
          )
          .frame(width: Layout.iconWidth)
          .accessibilityHidden(true)

        Text(String(localized: "Card Remote Access"))
          .font(.body)

        Spacer()

        Toggle("", isOn: remoteAccessBinding)
          .labelsHidden()
          .accessibilityIdentifier("remoteAccessToggle")
      }
    }
  }

  @ViewBuilder internal var pairingPhaseSection: some View {
    switch pairingModel.phase {
    case .offer(let code):
      Section {
        offeringCodeCard(code: code)
      }
    case .connecting:
      Section {
        connectingCard
      }
    case .paired(let peer):
      Section {
        pairedCard(peer: peer)
      }
    case .failed(let reason):
      Section {
        failedCard(reason: reason)
      }
    case .idle, .codeEntry:
      EmptyView()
    }
  }

  private var connectingCard: some View {
    VStack(spacing: Layout.contentSpacing) {
      ProgressView()
        .controlSize(.regular)
      Text(String(localized: "Connecting..."))
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, Layout.statusVerticalPadding)
  }

  internal var pairedDevicesSection: some View {
    Section(header: Text(String(localized: "Paired computers"))) {
      if pairingModel.pairs.isEmpty {
        Text(String(localized: "No paired computers"))
          .foregroundStyle(.secondary)
      } else {
        ForEach(pairingModel.pairs, id: \.pairID) { pair in
          pairedPeerRow(pair)
        }
      }
    }
  }

  private var peerConnectedBadge: some View {
    Text(String(localized: "Connected"))
      .font(.caption.weight(.semibold))
      .foregroundStyle(.green)
      .padding(.horizontal, Layout.badgeHorizontalPadding)
      .padding(.vertical, Layout.badgeVerticalPadding)
      .background(Color.green.opacity(Layout.badgeOpacity))
      .clipShape(Capsule())
  }

  private var peerDisconnectButton: some View {
    Button {
      #if REFINEID_LOCAL_CARD && os(iOS)
        PhonePersistentTokenRelay.shared.stopListening()
        PhonePersistentTokenRelay.shared.resumeAfterUserAction()
      #endif
    } label: {
      Image(systemName: "xmark")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(String(localized: "Disconnect"))
  }

  // MARK: - Methods

  private func offeringCodeCard(code: String) -> some View {
    VStack(spacing: Layout.cardSpacing) {
      Text(RappPairingCode.formatted(code))
        .font(.system(size: Layout.codeFontSize, weight: .bold, design: .monospaced))
        .tracking(Layout.codeTracking)
        .foregroundStyle(Color.accentColor)
        .padding(.top, Layout.codeTopPadding)
        .textSelection(.enabled)
        .accessibilityIdentifier("pairingCode")
        .accessibilityLabel(code)

      Button {
        pairingModel.createOffer()
      } label: {
        Text(String(localized: "Regenerate code"))
          .font(.body.weight(.medium))
          .frame(maxWidth: .infinity)
          .padding(.vertical, Layout.buttonVerticalPadding)
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("regenerateCodeButton")
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, Layout.verticalCardPadding)
  }

  private func pairedCard(peer: RappPairingCoordinator.PairSummary) -> some View {
    let name = RappPairNames.name(forPairID: peer.pairID) ?? String(localized: "Computer")
    return VStack(spacing: Layout.contentSpacing) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: Layout.statusIconSize))
        .foregroundStyle(.green)
        .accessibilityHidden(true)
      Text(String(localized: "Connected to \(name)"))
        .font(.headline)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, Layout.statusVerticalPadding)
  }

  private func failedCard(reason: String) -> some View {
    VStack(spacing: Layout.contentSpacing) {
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: Layout.statusIconSize))
        .foregroundStyle(.red)
        .accessibilityHidden(true)
      Text(String(localized: "Pairing failed"))
        .font(.headline)
      Text(reason)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button(String(localized: "Retry")) {
        pairingModel.createOffer()
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, Layout.statusVerticalPadding)
  }

  private func pairedPeerRow(_ pair: RappPairingCoordinator.PairSummary) -> some View {
    let name = RappPairNames.name(forPairID: pair.pairID) ?? String(localized: "Computer")
    let isConnected =
      isActivelyConnected
      && (PersistentTokenRegistry.activePairID == pair.pairID || pairingModel.pairs.count == 1)

    return HStack {
      VStack(alignment: .leading, spacing: Layout.textLineSpacing) {
        Text(name)
          .font(.body.weight(.medium))
          .foregroundStyle(.primary)
        Text(pair.remotePlatformLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isConnected {
        peerConnectedBadge
        peerDisconnectButton
      }
      peerDeleteButton(for: pair.pairID)
    }
  }

  private func peerDeleteButton(for pairID: Data) -> some View {
    Button(role: .destructive) {
      pairingModel.revoke(pairID: pairID)
    } label: {
      Image(systemName: "trash")
        .foregroundStyle(.red)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(String(localized: "Forget"))
    .accessibilityIdentifier("removePairButton")
  }
}
