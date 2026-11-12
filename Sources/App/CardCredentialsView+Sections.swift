// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardCredentialsView {
  #if os(iOS)
    private var verifyRow: some View {
      NavigationLink(value: Route.verifyDocuments) {
        MenuRow(
          String(localized: "verify.title", defaultValue: "Verify", table: "DocumentSigning"),
          systemImage: Self.verificationSymbolName,
          tint: .accentColor
        )
      }
      .accessibilityIdentifier("verifyDocuments")
    }

    private var signRow: some View {
      Button {
        synchronizeIdentityState()
        transition(.openDocumentSigning)
      } label: {
        MenuRow(
          String(localized: "signing.title", defaultValue: "Sign", table: "DocumentSigning"),
          systemImage: "signature",
          tint: .accentColor
        ) {
          DisclosureChevron()
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("signDocuments")
    }

    internal var signingSection: some View {
      Section {
        verifyRow
        if signingAvailable {
          signRow
        }
      } header: {
        CompactSectionHeader(
          title: String(
            localized: "signing.document", defaultValue: "Document", table: "DocumentSigning"))
      }
    }

    private var cardManagementRow: some View {
      Button {
        openCardManagement()
      } label: {
        MenuRow(String(localized: "Personal Identification Numbers (PINs)")) {
          CredentialRetryHealthKey(
            level: retryHealth.level,
            systemName: "key.2.on.ring",
            routeAvailable: managementAvailable)
        } trailing: {
          DisclosureChevron()
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("manageCard")
      .disabled(!managementAvailable)
    }

    internal var cardSection: some View {
      Section {
        switch mode {
        case .setup:
          // Setup renders the three setup actions instead of this section.
          EmptyView()

        case .identity, .readerIdentity:
          if SupportedCardTransports.servesRemoteCards {
            remoteAccessRow
          }
          cardManagementRow

        case .holding, .remoteOnly:
          EmptyView()
        }
        #if REFINEID_LOCAL_CARD
          if let failure = primingModel.failure {
            CredentialOutcomeText(message: failure, tone: .failure)
              .accessibilityIdentifier("primeFailureMessage")
          }
        #endif
      } header: {
        CompactSectionHeader(title: String(localized: "Card"))
      }
      .onAppear {
        syncRemoteAccessToggle()
        pairingModel.refresh()
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
    }

    private var remoteAccessRow: some View {
      NavigationLink(value: Route.remoteAccess) {
        MenuRow(
          String(localized: "Remote Access"),
          systemImage: remoteAccessSymbolName,
          tint: remoteAccessTint
        ) {
          if isActivelyConnected {
            connectedBadge
          }
        }
      }
      .accessibilityIdentifier("RappPairingRow")
    }

    /// The Mac switch's symbol, slashed while remote use is off.
    private var remoteAccessSymbolName: String {
      remoteAccessEnabled ? RemoteUseSymbol.enabled : RemoteUseSymbol.disabled
    }

    private var remoteAccessTint: Color {
      if isActivelyConnected {
        .green
      } else if remoteAccessEnabled {
        .accentColor
      } else {
        .secondary
      }
    }

    private var connectedBadge: some View {
      Text(String(localized: "Connected"))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.green)
        .padding(.horizontal, Layout.connectedBadgeHorizontalPadding)
        .padding(.vertical, Layout.connectedBadgeVerticalPadding)
        .background(Color.green.opacity(Layout.connectedBadgeOpacity))
        .clipShape(Capsule())
    }

    internal var readerIdentitySection: some View {
      CardReaderIdentitySection(holders: readerHolders)
    }
  #endif

  #if os(macOS)
    internal var readerIdentitySection: some View {
      EmptyView()
    }
  #endif

  @ViewBuilder internal var createIdentitySection: some View {
    #if os(iOS)
      EmptyView()
    #else
      Section {
        TextField(
          "Card Access Number (CAN)",
          text: $cardAccessNumberEntry
        )
        .font(.body)
        // A macOS form field otherwise gives VoiceOver its title only as
        // placeholder text.
        .accessibilityLabel(Text("Card Access Number (CAN)"))
        .accessibilityIdentifier("cardAccessNumberField")
        .onValueChange(of: cardAccessNumberEntry) { typed in
          cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
        }
      } header: {
        CompactSectionHeader(title: String(localized: "Connect"))
      }
    #endif
  }
}
