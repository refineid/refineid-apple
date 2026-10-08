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
          cardAccessNumberRow
          pin1Row

        case .identity, .readerIdentity:
          remoteAccessRow
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

    private var remoteAccessRow: some View {
      NavigationLink(value: Route.remoteAccess) {
        MenuRow(
          String(localized: "Remote Access"),
          systemImage: "antenna.radiowaves.left.and.right",
          tint: remoteAccessTint
        ) {
          if isActivelyConnected {
            connectedBadge
          }
        }
      }
      .accessibilityIdentifier("RappPairingRow")
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

    @ViewBuilder internal var readIdentityCardSection: some View {
      if mode == .setup {
        Section {
          readIdentityCardButton
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
      }
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
        cardAccessNumberRow
      } header: {
        CompactSectionHeader(title: String(localized: "Connect"))
      }
      Section {
        pin1Row
      } header: {
        CompactSectionHeader(title: String(localized: "Cache"))
      }
    #endif
  }

  @ViewBuilder internal var cardAccessNumberRow: some View {
    #if os(iOS)
      HStack {
        PersonRowLabel.cardIcon(
          systemName: "person.text.rectangle",
          lit: isCardAccessNumberEntryComplete
        )
        TextField(
          "Card Access Number (CAN)",
          text: $cardAccessNumberEntry
        )
        .font(.body)
        .keyboardType(.numberPad)
        .textContentType(nil)
        .focused($isCardAccessNumberFieldFocused)
        .accessibilityIdentifier("cardAccessNumberField")
        .onValueChange(of: cardAccessNumberEntry) { typed in
          cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
        }
        #if REFINEID_LOCAL_CARD && os(iOS)
          canScanButton
        #endif
      }
      .buttonStyle(.borderless)
    #else
      TextField(
        "Card Access Number (CAN)",
        text: $cardAccessNumberEntry
      )
      .font(.body)
      .accessibilityIdentifier("cardAccessNumberField")
      .onValueChange(of: cardAccessNumberEntry) { typed in
        cardAccessNumberEntry = LimitedDigits.cardAccessNumber(typed)
      }
    #endif
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    @ViewBuilder private var canScanButton: some View {
      if CardAccessNumberScanner.isAvailable {
        Button {
          scannerTorchEnabled = false
          isScanning = true
        } label: {
          Label("Scan", systemImage: "camera")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .frame(width: Layout.canButtonSize, height: Layout.canButtonSize)
        .contentShape(Rectangle())
        .padding(Layout.canButtonOuterPadding)
      }
    }
  #endif

  #if os(iOS)
    private var readIdentityCardButton: some View {
      Button {
        isCardAccessNumberFieldFocused = false
        isPin1FieldFocused = false
        connectIdentityCard()
      } label: {
        Label(
          String(localized: "Read Identity Card"),
          systemImage: "person.badge.key.fill"
        )
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.primaryActionButtonHeight)
        .background(
          canReadIdentityCard
            ? Color.accentColor : Color.secondary.opacity(Layout.disabledActionOpacity),
          in: Capsule()
        )
        .contentShape(Capsule())
      }
      .buttonStyle(.borderless)
      .disabled(!canReadIdentityCard)
      .accessibilityIdentifier("primeStartButton")
    }
  #endif

  @ViewBuilder internal var pin1Row: some View {
    #if os(iOS)
      HStack {
        PersonRowLabel.cardIcon(systemName: "key", lit: isPin1Cached)
        CredentialSecretField(
          name: String(localized: "Basic Code (PIN 1)"),
          text: $pin1Entry,
          revealIdentifier: "pin1FieldReveal"
        ) {
          SecureField("Basic Code (PIN 1)", text: $pin1Entry)
            .font(.body)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isPin1FieldFocused)
            .accessibilityIdentifier("pin1Field")
            .onValueChange(of: pin1Entry) { typed in
              pin1Entry = LimitedDigits.pin1(typed)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
          dimensions[.leading]
        }
      }
      .buttonStyle(.borderless)
    #else
      CredentialSecretField(
        name: String(localized: "Basic Code (PIN 1)"),
        text: $pin1Entry,
        revealIdentifier: "pin1FieldReveal"
      ) {
        SecureField("Basic Code (PIN 1)", text: $pin1Entry)
          .font(.body)
          .autocorrectionDisabled()
          .focused($isPin1FieldFocused)
          .accessibilityIdentifier("pin1Field")
          .onValueChange(of: pin1Entry) { typed in
            pin1Entry = LimitedDigits.pin1(typed)
          }
      }
    #endif
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    internal var scannerSheet: some View {
      ScannerSheet(
        torchEnabled: $scannerTorchEnabled,
        isScanning: $isScanning
      ) { digits in
        cardAccessNumberEntry = digits
      }
    }
  #endif
}
