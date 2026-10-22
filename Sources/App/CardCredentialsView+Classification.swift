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
      transition(.classificationFailed)
    }
  }

  private func handleActivated(entered: String, purpose _: CardConnectionPurpose) {
    if !isDemonstration, !model.saveCardAccessNumber(entered) {
      cardAccessNumberEntry = ""
      isCardAccessNumberFieldFocused = true
      transition(.classificationFailed)
      return
    }
    if retryHealth.recovery != nil {
      transition(.classificationRecoveryRequired)
      return
    }
    transition(.classificationActivated)
  }

  private func handleActivationRequired(
    scheme: ActivationScheme,
    needs: CardActivationNeeds
  ) {
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
    guard isCardAccessNumberEntryComplete else {
      #if DEBUG
        DebugConsole.emit("connectIdentityCard: guard failed, access number incomplete")
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
          model: primingModel,
          commit: IdentityCommitments(storeCardAccessNumber: storeProvenCardAccessNumber) {
            isRegistered = true
          })
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
          transition(.classificationWrongCardAccessNumber)
        }

      case .activationRequired(let scheme, let needs):
        activationScheme = scheme
        activationNeeds = needs
        transition(.classificationActivationRequired)

      case .secureChannelTimedOut, nil:
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

  /// Empties the field once it has nothing left to describe.
  internal func clearEntries() {
    cardAccessNumberEntry = ""
    isCardAccessNumberFieldFocused = false
  }
}
