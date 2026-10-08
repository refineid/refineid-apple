// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if os(iOS)
  extension CardCredentialsView {
    // MARK: Nested Types

    private enum RemoteReaderLayout {
      static let tapTargetSide: CGFloat = 44
      static let forgetButtonGap: CGFloat = 4
      static let identityDetailsSpacing: CGFloat = 4
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
          VStack(alignment: .leading, spacing: RemoteReaderLayout.identityDetailsSpacing) {
            PersonRowLabel(configured: true)
            Text(holder)
              .font(.body)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .accessibilityIdentifier("remoteCardHolder")
          }
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
        if case .failed(let message) = pairingModel.phase {
          Text(message)
            .foregroundStyle(.secondary)
        }
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
