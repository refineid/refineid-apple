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
      #if os(iOS)
        if isRemoteAccessEnabled {
          NotificationsOffRow()
        }
      #endif
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
    case .failed(let failure) where failure.opensNetworkSettings:
      Section {
        LocalNetworkNotice(message: failure.message)
      }
    case .failed(.locked(let until)):
      Section {
        TimelineView(.periodic(from: .now, by: PairingLockCountdown.tick)) { context in
          failedCard(reason: PairingLockCountdown.message(until: until, at: context.date))
        }
      }
    case .failed(let failure):
      Section {
        failedCard(reason: failure.message)
      }
    case .idle, .codeEntry, .paired:
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

  @ViewBuilder internal var pairedDevicesSection: some View {
    let named = pairingModel.pairs.map { pair in
      (pairID: pair.pairID, name: RappPairNames.displayName(forPairID: pair.pairID))
    }
    if !named.isEmpty {
      Section(header: Text(String(localized: "Paired computers"))) {
        ForEach(named, id: \.pairID) { peer in
          pairedPeerRow(pairID: peer.pairID, name: peer.name)
        }
      }
    }
  }

  // MARK: - Methods

  private func offeringCodeCard(code: String) -> some View {
    VStack(spacing: Layout.cardSpacing) {
      Text(RappPairingCode.formatted(code))
        .font(.system(size: Layout.codeFontSize, weight: .bold, design: .monospaced))
        .tracking(Layout.codeTracking)
        .foregroundStyle(.primary)
        .padding(.top, Layout.codeTopPadding)
        .textSelection(.enabled)
        .accessibilityIdentifier("pairingCode")
        .accessibilityLabel(code.map(String.init).joined(separator: " "))
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, Layout.verticalCardPadding)
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
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, Layout.statusVerticalPadding)
  }

  private func pairedPeerRow(pairID: Data, name: String) -> some View {
    HStack {
      Text(name)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
      Spacer()
      peerDeleteButton(for: pairID)
    }
  }

  private func peerDeleteButton(for pairID: Data) -> some View {
    Button(role: .destructive) {
      Task { await pairingModel.forget(pairID: pairID) }
    } label: {
      Image(systemName: "trash")
        .foregroundStyle(.red)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(String(localized: "Forget"))
    .accessibilityIdentifier("removePairButton")
  }
}
