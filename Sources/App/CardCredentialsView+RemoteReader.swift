// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(iOS)
  extension CardCredentialsView {
    // MARK: Nested Types

    private enum RemoteReaderLayout {
      static let tapTargetSide: CGFloat = 44
      static let forgetButtonGap: CGFloat = 4
    }

    @ViewBuilder private var remoteActionContent: some View {
      switch pairingModel.phase {
      case .codeEntry, .connecting, .failed:
        PairingCodeEntryField(model: pairingModel)

      case .idle, .offer, .paired:
        Button(String(localized: "Connect")) {
          withAnimation {
            pairingModel.startCodeEntry()
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
          PersonRowLabel.cardIcon(systemName: "person.fill.checkmark", lit: true)
          Text(holder)
            .textSelection(.enabled)
            .accessibilityIdentifier("remoteCardHolder")
          Spacer(minLength: RemoteReaderLayout.forgetButtonGap)
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
            width: RemoteReaderLayout.tapTargetSide,
            height: RemoteReaderLayout.tapTargetSide
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
        // The paired phone holds no card: ask for it the way its reader
        // allows (RAPP v26.10.22 §8.4 item 6).
        if let request = PersistentTokenRegistry.shared.holderCardRequest {
          PhoneCardRequestLine(request: request)
        }
        if case .failed(let failure) = pairingModel.phase {
          if failure.opensNetworkSettings {
            LocalNetworkNotice(message: failure.message)
          } else {
            Text(failure.message)
              .foregroundStyle(.secondary)
          }
        } else if PersistentTokenRegistry.shared.localNetworkDenied {
          LocalNetworkNotice(message: LocalNetworkSettings.deniedMessage)
        }
        if remoteModel.phase == .failed {
          Text(remoteModel.failureText ?? String(localized: "The remote card could not be read."))
            .foregroundStyle(.secondary)
        }
      } header: {
        CompactSectionHeader(title: String(localized: "Identity"))
      }
      .onValueChange(of: remoteModel.needsFreshPairing) { needsFresh in
        if needsFresh {
          remoteModel.acknowledgeFreshPairing()
          pairingModel.startCodeEntry()
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
      ) { _ in
        // Back from the settings: the code is offered afresh.
        if pairingModel.phase == .failed(.localNetworkDenied) {
          pairingModel.startCodeEntry()
        }
      }
      .onReceive(pairingModel.$phase) { phase in
        if case .paired = phase {
          remoteModel.refreshThenConnect()
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
