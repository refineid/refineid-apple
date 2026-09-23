// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardCredentialsView {
  /// The screen's identity area: exactly one of the hold blank, the
  /// live reader identity, the reader-only notice, the set identity,
  /// or the setup form.
  @ViewBuilder internal var identityArea: some View {
    if isHolding {
      EmptyView()
    } else if hasReaderIdentity {
      readerIdentitySection
    } else if !offersNearField {
      remoteReaderSection
    } else if let identityHolder {
      CardIdentitySection(holder: identityHolder) {
        showsForgetConfirmation = true
      }
    } else {
      createIdentitySection
    }
  }

  /// The form and its navigation chrome.
  internal var navigationChrome: some View {
    Form {
      #if os(iOS)
        if !isHolding {
          signingSection
          if offersNearField || hasReaderIdentity {
            cardSection
            readIdentityCardSection
          }
        }
      #endif
      #if !os(iOS)
        if !isHolding {
          managementSection
        }
      #endif
      identityArea
      if let failure = model.failure, !isHolding {
        Section {
          CredentialOutcomeText(message: failure, tone: .failure)
        }
      }
    }
    #if os(iOS)
      .listSections(spacing: Self.sectionSpacing)
      .scrollDismissesKeyboard(.interactively)
      .onTapGesture {
        isCardAccessNumberFieldFocused = false
        isPin1FieldFocused = false
      }
      .navigationDestination(
        isPresented: Binding(
          get: { flowDestination.wrappedValue != nil },
          set: { presented in
            if !presented { flowDestination.wrappedValue = nil }
          }
        )
      ) {
        if let destination = flowDestination.wrappedValue {
          destinationView(destination)
        }
      }
      .navigationDestination(isPresented: $showsDocumentVerify) {
        VerifyDocumentView()
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
      .alert(
        "Forget identity?",
        isPresented: $showsForgetConfirmation
      ) {
        Button("Forget", role: .destructive) {
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
      }
  }

  internal func navigationRow(
    _ title: String,
    @ViewBuilder icon: () -> some View
  ) -> some View {
    HStack {
      icon()
        .font(.system(size: PersonRowLabel.iconPointSize))
        .symbolRenderingMode(.monochrome)
        .frame(width: PersonRowLabel.iconWidth)
        .accessibilityHidden(true)
      Text(title)
      Spacer()
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
  }

  internal func compactSectionHeader(
    _ title: LocalizedStringKey
  ) -> some View {
    Text(title)
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowInsets(EdgeInsets())
  }

  internal func compactSectionHeader(verbatim title: String) -> some View {
    Text(title)
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowInsets(EdgeInsets())
  }

  #if os(iOS)
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
        if hasReaderIdentity {
          CardManagementView(
            readerCardIsPresent: true,
            activationRequired: false,
            cardAccessNumber: nil,
            activationScheme: nil,
            activationNeeds: nil,
            onActivationSucceeded: {
              // optional hook; default is a no-op
            }
          )
          .id(CardSetupStateMachine.Destination.pinManagement)
        } else {
          CardManagementView(
            readerCardIsPresent: false,
            activationRequired: false,
            cardAccessNumber: managementCardAccessNumber,
            activationScheme: nil,
            activationNeeds: nil,
            onActivationSucceeded: {
              // optional hook; default is a no-op
            }
          )
          .id(CardSetupStateMachine.Destination.pinManagement)
        }

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
