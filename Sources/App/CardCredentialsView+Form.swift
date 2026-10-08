// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardCredentialsView {
  /// The screen's identity area, by mode.
  @ViewBuilder internal var identityArea: some View {
    switch mode {
    case .holding:
      EmptyView()

    case .readerIdentity:
      readerIdentitySection

    case .remoteOnly:
      remoteReaderSection

    case .identity(let holder):
      CardIdentitySection(holder: holder)

    case .setup:
      createIdentitySection
    }
  }

  /// The form and its navigation chrome.
  internal var navigationChrome: some View {
    Form {
      #if os(iOS)
        if mode != .holding {
          signingSection
          if mode != .remoteOnly {
            cardSection
            readIdentityCardSection
          }
        }
      #else
        if mode != .holding {
          managementSection
        }
      #endif
      identityArea
      if let failure = model.failure, mode != .holding {
        Section {
          CredentialOutcomeText(message: failure, tone: .failure)
        }
      }
    }
    #if os(iOS)
      .listSections(spacing: Self.sectionSpacing)
      .scrollDismissesKeyboard(.interactively)
      .navigationDestination(item: flowDestination) { destination in
        destinationView(destination)
      }
      .navigationDestination(for: Route.self) { route in
        routeView(route)
      }
    #endif
  }

  internal var credentialsForm: some View {
    navigationChrome
      .safeAreaInset(edge: .bottom) {
        #if os(iOS)
          let includesFooter = !demoMode.isEditorPresented
        #else
          let includesFooter = true
        #endif
        if includesFooter {
          let hidesFooter =
            isCardAccessNumberFieldFocused || isPin1FieldFocused
          CardSetupFooter(isDemonstration: isDemonstration)
            .opacity(hidesFooter ? 0 : 1)
            .allowsHitTesting(!hidesFooter)
            .accessibilityHidden(hidesFooter)
        }
      }
      .onAppear {
        model.refresh()
        refreshRegistration()
        showStoredCardAccessNumber()
        synchronizeIdentityState()
        #if DEBUG && os(iOS)
          if ProcessInfo.processInfo.arguments.contains("--open-document-signing") {
            transition(.openDocumentSigning)
          }
        #endif
      }
      #if os(iOS)
        .task(id: readerHolderReadKey) {
          readerHolders = await readerModel?.holderNames() ?? []
        }
      #endif
      .onValueChange(of: hasIdentity) { registered in
        if registered {
          showStoredCardAccessNumber()
          finishBrowserRegistration(succeeded: true)
          clearPin1Entry()
        } else {
          synchronizeIdentityState()
        }
      }
      .onValueChange(of: model.contents) { _ in
        showStoredCardAccessNumber()
      }
      #if os(iOS)
        .onReceive(
          NotificationCenter.default.publisher(
            for: VirtualIDCardOverlayNotification.editorDidDismiss)
        ) { _ in
          isCardAccessNumberFieldFocused = false
          isPin1FieldFocused = false
        }
      #endif
      .onValueChange(of: isCardAccessNumberEntryComplete) { complete in
        if complete {
          #if os(iOS)
            isPin1FieldFocused = true
          #endif
          return
        }
        pin1Entry = ""
        isPin1FieldFocused = false
        #if os(iOS)
          if isDemonstration {
            demoMode.forgetIdentity()
          }
        #endif
      }
      .onValueChange(of: cardAccessNumberEntry) { entered in
        model.invalidateCardStatus()
        activationScheme = nil
        activationNeeds = nil
        if !entered.isEmpty {
          model.clearFailure()
        }
        guard entered.isEmpty,
          !isDemonstration,
          model.contents.hasCardAccessNumber
        else { return }
        Task { await model.forgetEverything() }
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: CardCredentialStore.cardAccessNumberDidInvalidate)
      ) { _ in
        model.refresh()
        cardAccessNumberEntry = ""
        clearPin1Entry()
        activationScheme = nil
        activationNeeds = nil
        model.invalidateCardStatus()
        isCardAccessNumberFieldFocused = true
      }
      #if REFINEID_LOCAL_CARD && os(iOS)
        .sheet(isPresented: $isScanning) {
          scannerSheet
        }
      #endif
  }

  internal func forgetCurrentIdentity() {
    #if os(iOS)
      if isDemonstration {
        if let holder = identityHolder {
          CardPhotoStore.deletePhoto(for: holder)
        }
        demoMode.forgetIdentity()
        clearEntries()
        return
      }
    #endif
    Task {
      if let holder = identityHolder {
        CardPhotoStore.deletePhoto(for: holder)
      }
      await model.forgetEverything()
      registrationReset.toggle()
      isRegistered = false
      synchronizeIdentityState()
      clearEntries()
    }
  }

  #if os(iOS)
    @ViewBuilder
    internal func routeView(_ route: Route) -> some View {
      switch route {
      case .verifyDocuments:
        VerifyDocumentView()

      case .remoteAccess:
        RappPairingView()

      case .identity(.phone(let holder)):
        CardIdentitySubmenuView(
          holder: holder,
          identifier: identityIdentifier,
          onForget: forgetCurrentIdentity,
          onReadPhoto: { can in
            await readCardPhoto(for: holder, accessNumber: can)
          }
        )

      case .identity(.reader(let holder)):
        CardIdentitySubmenuView(
          holder: holder,
          identifier: nil,
          onForget: nil,
          onReadPhoto: { can in
            await readCardPhoto(for: holder, accessNumber: can)
          }
        )
      }
    }

    @ViewBuilder
    internal func destinationView(
      _ destination: CardSetupStateMachine.Destination
    ) -> some View {
      switch destination {
      case .activation:
        #if DEBUG
          let _: Void = DebugConsole.emit("navigation-destination: activation")
        #endif
        if let activationScheme, let activationNeeds {
          CardManagementView(
            readerCardIsPresent: false,
            activationRequired: true,
            cardAccessNumber: cardAccessNumberEntry,
            activationScheme: activationScheme,
            activationNeeds: activationNeeds,
            onActivationSucceeded: activationSucceeded
          )
          .id(CardSetupStateMachine.Destination.activation)
        }

      case .pinManagement:
        #if DEBUG
          let _: Void = DebugConsole.emit("navigation-destination: PIN management")
        #endif
        CardManagementView(
          readerCardIsPresent: hasReaderIdentity,
          activationRequired: false,
          cardAccessNumber: hasReaderIdentity ? nil : managementCardAccessNumber
        )
        .id(CardSetupStateMachine.Destination.pinManagement)

      case .signDocuments:
        DocumentSigningView(
          transport: hasReaderIdentity ? .reader : .nearField,
          cardAccessNumber: hasReaderIdentity ? nil : managementCardAccessNumber
        )
        .id(CardSetupStateMachine.Destination.signDocuments)
      }
    }
  #endif
}
