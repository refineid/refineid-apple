// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardCredentialsView {
  #if os(iOS)
    private var verifyRouteButton: some View {
      Button {
        showsDocumentVerify = true
      } label: {
        navigationRow(
          String(
            localized: "verify.title",
            defaultValue: "Verify",
            table: "DocumentSigning")
        ) {
          Image(systemName: Self.verificationSymbolName)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("verifyDocuments")
    }

    private var signRouteButton: some View {
      Button {
        synchronizeIdentityState()
        transition(.openDocumentSigning)
      } label: {
        navigationRow(
          String(
            localized: "signing.title",
            defaultValue: "Sign",
            table: "DocumentSigning")
        ) {
          Image(systemName: "signature")
            .foregroundStyle(
              signingAvailable
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(.secondary)
            )
            .accessibilityHidden(true)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("signDocuments")
      .disabled(!signingAvailable)
    }

    internal var signingSection: some View {
      Section {
        verifyRouteButton
        if signingAvailable {
          signRouteButton
        }
      } header: {
        compactSectionHeader(
          verbatim: String(
            localized: "signing.document",
            defaultValue: "Document",
            table: "DocumentSigning"))
      }
    }

    private var cardManagementButton: some View {
      Button {
        openCardManagement()
      } label: {
        navigationRow(
          String(localized: "Personal Identification Numbers (PINs)")
        ) {
          CredentialRetryHealthKey(
            level: retryHealth.level,
            systemName: "key.2.on.ring",
            routeAvailable: managementAvailable)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("manageCard")
      .disabled(!managementAvailable)
    }

    internal var cardSection: some View {
      Section {
        if offersNearField, !hasReaderIdentity, identityHolder == nil {
          cardAccessNumberRow
          pin1Row
        }
        if identityHolder != nil || hasReaderIdentity {
          cardManagementButton
          remoteAccessToggleRow
          remotePairingCodeRow
        }
        #if REFINEID_LOCAL_CARD
          if let failure = primingModel.failure {
            CredentialOutcomeText(message: failure, tone: .failure)
              .accessibilityIdentifier("primeFailureMessage")
          }
        #endif
      } header: {
        compactSectionHeader("Card")
      }
      .onAppear {
        syncRemoteAccessToggle()
        pairingModel.refresh()
        RappAutoPairingService.shared.reconcile()
        #if os(iOS) && REFINEID_LOCAL_CARD
          phoneRelay.updatePeerOnlineState()
        #endif
      }
      .onReceive(pairingModel.$phase) { phase in
        if case .paired = phase {
          withAnimation {
            pairingCodeDigits = ""
          }
        }
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

    @ViewBuilder internal var readIdentityCardSection: some View {
      if offersNearField, !hasReaderIdentity, identityHolder == nil {
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
        compactSectionHeader("Connect")
      }
      Section {
        pin1Row
      } header: {
        compactSectionHeader("Cache")
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
