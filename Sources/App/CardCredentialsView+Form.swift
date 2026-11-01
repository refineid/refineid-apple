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
      CardIdentitySection(holder: holder, onRemove: forgetCurrentIdentity)

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
          let hidesFooter = isCardAccessNumberFieldFocused
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
        }
      #endif
      .onValueChange(of: isCardAccessNumberEntryComplete) { complete in
        guard !complete else { return }
        #if os(iOS)
          if isDemonstration {
            demoMode.forgetIdentity()
          }
        #endif
      }
      .onValueChange(of: cardAccessNumberEntry) { entered in
        model.invalidateCardStatus()
        activation = nil
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
        activation = nil
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
        demoMode.forgetIdentity()
        clearEntries()
        return
      }
    #endif
    Task {
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
        if let activation, let activationNeeds {
          CardManagementView(
            readerCardIsPresent: false,
            activationRequired: true,
            cardAccessNumber: cardAccessNumberEntry,
            activation: activation,
            activationNeeds: activationNeeds,
            onActivationSucceeded: activationSucceeded
          )
          .id(CardSetupStateMachine.Destination.activation)
          // Only the bar's back button leaves activation: hiding the
          // system one also disables the edge swipe, which closed the
          // screen by accident mid-entry.
          .navigationBarBackButtonHidden(true)
          .toolbar {
            ToolbarItem(placement: .navigation) {
              Button {
                flowDestination.wrappedValue = nil
              } label: {
                Label("Back", systemImage: "chevron.backward")
              }
              .accessibilityIdentifier("activationBack")
            }
          }
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
