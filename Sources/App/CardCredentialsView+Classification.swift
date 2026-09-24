// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardCredentialsView {
  // MARK: Functions

  /// Puts a stored card access number back in its field.
  internal func showStoredCardAccessNumber() {
    #if os(iOS)
      if isDemonstration {
        guard cardAccessNumberEntry.isEmpty else { return }
        cardAccessNumberEntry = demoMode.displayedCardAccessNumber ?? ""
        return
      }
    #endif
    guard cardAccessNumberEntry.isEmpty, let stored = model.storedCardAccessNumber else {
      return
    }
    cardAccessNumberEntry = stored
  }

  /// Reads the persistent registration state, on the platform that has it.
  internal func refreshRegistration() {
    #if REFINEID_LOCAL_CARD && os(iOS)
      isRegistered = CardRegistrationSections.hasRegisteredIdentity
    #endif
  }

  /// Returns the transient PIN only to the card-reading operation.
  @MainActor
  internal func enteredPin1() -> String? {
    guard isPin1EntryComplete else { return nil }
    isPin1FieldFocused = false
    return pin1Entry
  }

  /// Removes PIN1 from UI memory after every completed NFC operation.
  @MainActor
  internal func clearPin1Entry() {
    pin1Entry = ""
    isPin1FieldFocused = false
  }

  /// One side-effect-free NFC snapshot decides activation, recovery, and the
  /// healthy path before PIN management opens.
  internal func classifyIdentityCard(for purpose: CardConnectionPurpose) {
    guard isCardAccessNumberEntryComplete, !model.isConnecting else { return }
    guard transition(.startManagementClassification) else { return }
    let entered = cardAccessNumberEntry
    activationScheme = nil
    activationNeeds = nil
    isCardAccessNumberFieldFocused = false
    Task {
      await processClassification(entered: entered, purpose: purpose)
    }
  }

  private func processClassification(
    entered: String,
    purpose: CardConnectionPurpose
  ) async {
    guard let result = await model.connect(cardAccessNumber: entered) else {
      transition(.classificationFailed)
      return
    }
    guard entered == cardAccessNumberEntry else {
      model.invalidateCardStatus()
      transition(.classificationFailed)
      return
    }
    handleClassificationResult(result, entered: entered, purpose: purpose)
  }

  private func handleClassificationResult(
    _ result: CardCredentialsModel.ConnectionResult,
    entered: String,
    purpose: CardConnectionPurpose
  ) {
    switch result {
    case .activated:
      handleActivated(entered: entered, purpose: purpose)

    case .activationRequired(let scheme, let needs):
      handleActivationRequired(scheme: scheme, needs: needs)

    case .wrongCardAccessNumber:
      handleWrongCardAccessNumber()

    case .failed:
      clearPin1Entry()
      transition(.classificationFailed)
    }
  }

  private func handleActivated(entered: String, purpose _: CardConnectionPurpose) {
    if !isDemonstration, !model.saveCardAccessNumber(entered) {
      cardAccessNumberEntry = ""
      clearPin1Entry()
      isCardAccessNumberFieldFocused = true
      transition(.classificationFailed)
      return
    }
    if retryHealth.recovery != nil {
      clearPin1Entry()
      transition(.classificationRecoveryRequired)
      return
    }
    clearPin1Entry()
    transition(.classificationActivated)
  }

  private func handleActivationRequired(
    scheme: ActivationScheme,
    needs: CardActivationNeeds
  ) {
    if !isDemonstration {
      model.forgetPin1()
    }
    clearPin1Entry()
    activationScheme = scheme
    activationNeeds = needs
    transition(.classificationActivationRequired)
  }

  private func handleWrongCardAccessNumber() {
    if !isDemonstration, hasIdentity {
      Task { await model.forgetEverythingAfterCardMismatch() }
    }
    cardAccessNumberEntry = ""
    isCardAccessNumberFieldFocused = true
    clearPin1Entry()
    transition(.classificationWrongCardAccessNumber)
  }

  /// Activation succeeded on the card; only now is its CAN persistent.
  internal func activationSucceeded() {
    activationScheme = nil
    activationNeeds = nil
    if isDemonstration {
      showStoredCardAccessNumber()
      transition(.activationSucceeded)
      return
    }
    if !model.saveCardAccessNumber(cardAccessNumberEntry) {
      cardAccessNumberEntry = ""
      isCardAccessNumberFieldFocused = true
    }
    transition(.activationSucceeded)
  }

  /// Persistent identity is an input event, never an alternate navigation
  /// branch outside the reducer.
  internal func synchronizeIdentityState() {
    if hasIdentity, flowState == .home {
      transition(.identityLoaded)
    } else if !hasIdentity, flowState == .identityHome {
      transition(.identityForgotten)
    }
  }

  /// Commits verified PIN 1 at the device boundary.
  internal func storeVerifiedPin1(_ pin1: String) -> Bool {
    #if os(iOS)
      if isDemonstration {
        return demoMode.hasIdentity
      }
    #endif
    return model.savePin1(pin1)
  }

  /// Completes registration from the operation result instead of waiting for
  /// SwiftUI to observe a separate identity mutation.
  internal func finishBrowserRegistration(succeeded: Bool) {
    if flowState == .registeringBrowser {
      transition(succeeded ? .registrationSucceeded : .registrationFailed)
    } else if succeeded {
      synchronizeIdentityState()
    }
  }

  @discardableResult
  internal func transition(_ event: CardSetupStateMachine.Event) -> Bool {
    switch CardSetupStateMachine.reduce(state: flowState, event: event) {
    case .transitioned(let target):
      flowState = target
      return true

    case .rejected:
      return false
    }
  }

  /// The access number a registration hold should prove.
  @MainActor
  internal func registrationCardAccessNumber() -> String? {
    if isCardAccessNumberEntryComplete { return cardAccessNumberEntry }
    return CardCredentialStore.displayedCardAccessNumber()
  }

  /// Commits the access number at the device boundary, once proved.
  internal func storeProvenCardAccessNumber(_ digits: String) -> Bool {
    #if os(iOS)
      if isDemonstration { return demoMode.hasValidatedConnection }
    #endif
    return model.saveCardAccessNumber(digits)
  }

  /// Sets the identity up in one hold.
  internal func connectIdentityCard() {
    if !pin1Entry.isEmpty, !isPin1EntryComplete { return }
    let pin1 = enteredPin1()
    guard isCardAccessNumberEntryComplete, pin1 != nil || OnDemandPinExperiment.isEnabled else {
      #if DEBUG
        DebugConsole.emit(
          "connectIdentityCard: guard failed complete=\(isCardAccessNumberEntryComplete) pin1=\(pin1 != nil)"
        )
      #endif
      return
    }
    if flowState != .home {
      flowState = .home
    }
    guard transition(.startBrowserClassification) else {
      #if DEBUG
        DebugConsole.emit("connectIdentityCard: transition rejected from flowState=\(flowState)")
      #endif
      return
    }
    let entered = cardAccessNumberEntry
    activationScheme = nil
    activationNeeds = nil
    isCardAccessNumberFieldFocused = false
    model.clearFailure()
    model.invalidateCardStatus()
    Task { @MainActor in
      #if REFINEID_LOCAL_CARD && os(iOS)
        let succeeded = await CardRegistrationSections.registerIdentity(
          cardAccessNumber: entered,
          pin1: pin1,
          model: primingModel,
          commit: IdentityCommitments(
            storeCardAccessNumber: storeProvenCardAccessNumber,
            storeVerifiedPin1: storeVerifiedPin1,
            clearPin1Entry: clearPin1Entry
          ) { isRegistered = true })
        finishIdentitySetup(succeeded: succeeded)
      #else
        transition(.classificationFailed)
      #endif
    }
  }

  /// Routes the one hold's outcome, reading what the card said.
  @MainActor
  internal func finishIdentitySetup(succeeded: Bool) {
    #if REFINEID_LOCAL_CARD && os(iOS)
      retryHealth.update(primingModel.credentialReport)
      guard !succeeded else {
        if retryHealth.recovery != nil {
          clearPin1Entry()
          transition(.classificationRecoveryRequired)
          return
        }
        transition(.classificationActivated)
        finishBrowserRegistration(succeeded: true)
        return
      }
      switch primingModel.refusal {
      case .wrongCardAccessNumber:
        Task { @MainActor in
          if !isDemonstration, hasIdentity {
            await model.forgetEverythingAfterCardMismatch()
          }
          cardAccessNumberEntry = ""
          isCardAccessNumberFieldFocused = true
          clearPin1Entry()
          transition(.classificationWrongCardAccessNumber)
        }

      case .activationRequired(let scheme, let needs):
        clearPin1Entry()
        activationScheme = scheme
        activationNeeds = needs
        transition(.classificationActivationRequired)

      case nil:
        clearPin1Entry()
        transition(.classificationFailed)
      }
    #endif
  }

  /// A live reader identity opens management directly: its card is already present.
  internal func openCardManagement() {
    if hasReaderIdentity {
      synchronizeIdentityState()
      transition(.openVerifiedManagement)
      return
    }
    guard isCardAccessNumberEntryComplete, !model.isConnecting else { return }
    synchronizeIdentityState()
    if let activationNeeds, activationNeeds.any {
      transition(.openKnownActivation)
    } else if model.hasVerifiedCardStatus {
      transition(.openVerifiedManagement)
    } else {
      classifyIdentityCard(for: .pinManagement)
    }
  }

  /// Empties both fields once they have nothing left to describe.
  internal func clearEntries() {
    cardAccessNumberEntry = ""
    pin1Entry = ""
    isCardAccessNumberFieldFocused = false
    isPin1FieldFocused = false
  }
}
