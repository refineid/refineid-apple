// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

@MainActor
internal final class CardManagementModel: ObservableObject {
  @Published internal private(set) var report: CredentialProbeReport? {
    didSet { CredentialRetryHealth.shared.update(report) }
  }
  @Published internal private(set) var activationNeeds = CardMaintenance.ActivationNeeds(
    pin1: true,
    pin2: true
  )
  @Published internal private(set) var activation: ActivationClassification?
  /// The PIN and PUK lengths of the card the forms act on; the forms are
  /// drawn only once these are known.
  @Published internal private(set) var pinLengths: CardPinLengths?
  @Published internal private(set) var offersActivation = false
  @Published internal var working = false
  @Published internal var failure: String?
  @Published internal var notice: String?

  private let activationRequired: Bool
  private var nextRefreshIdentifier = 0
  private var activeRefreshIdentifier: Int?

  internal var cardOperationInProgress: Bool {
    working || activeRefreshIdentifier != nil
  }

  @Published internal var transport: CardMaintenance.Transport {
    didSet {
      guard transport != oldValue else { return }
      #if DEBUG
        DebugConsole.emit(
          "card-management: transport changed from \(oldValue) to \(transport); clearing activation offer"
        )
      #endif
      activeRefreshIdentifier = nil
      report = nil
      pinLengths = nil
      if !activationRequired {
        activation = nil
        offersActivation = false
      }
      failure = nil
      notice = nil
    }
  }

  @Published internal var cardAccessNumber: String
  internal let availableTransports = CardMaintenance.availableTransports

  internal var canContactCard: Bool {
    transport == .reader
      || cardAccessNumber.count == CardAccessNumber.digitCount
  }

  internal var offeredCardAccessNumber: String? {
    transport == .nearField ? cardAccessNumber : nil
  }

  internal var unreadableCardMessage: String {
    transport == .nearField
      ? String(
        localized:
          "The card could not be read over NFC. Check its card access number and try again.")
      : String(localized: "No readable card. Connect a reader and insert the card.")
  }

  internal init(
    transport: CardMaintenance.Transport?,
    activationRequired: Bool,
    cardAccessNumber: String?,
    activation: ActivationClassification?,
    activationNeeds: CardActivationNeeds?,
    pinLengths: CardPinLengths?
  ) {
    self.activationRequired = activationRequired
    self.transport = transport ?? CardMaintenance.preferredTransport
    self.activation = activation
    self.pinLengths = pinLengths
    if let activationNeeds {
      self.activationNeeds = activationNeeds
      offersActivation = activationRequired && activationNeeds.any
    } else {
      offersActivation = activationRequired
    }
    self.cardAccessNumber =
      cardAccessNumber ?? CardCredentialStore.displayedCardAccessNumber() ?? ""
    #if DEBUG
      DebugConsole.emit(
        "card-management: initialized activationRequired=\(activationRequired) "
          + "needs=\(String(describing: activationNeeds)) "
          + "offersActivation=\(offersActivation) transport=\(self.transport)"
      )
    #endif
  }

  internal func cardRemoved() {
    #if DEBUG
      DebugConsole.emit("card-management: card removed; clearing activation offer")
    #endif
    activeRefreshIdentifier = nil
    report = nil
    if !activationRequired {
      activation = nil
      offersActivation = false
      pinLengths = nil
    }
    failure = nil
    notice = nil
  }

  /// Reads only the activation classification and the PIN lengths the
  /// activation form needs.
  ///
  /// No retry counter changes; the form is drawn once both are in.
  internal func detectActivation() async {
    guard activationRequired || offersActivation, transport == .reader else { return }
    let detected = await CardMaintenance.readerActivation()
    guard activationRequired || offersActivation, transport == .reader else { return }
    activation = detected?.activation
    pinLengths = detected?.pinLengths
  }

  internal func refresh() async {
    guard !cardOperationInProgress, canContactCard else { return }
    #if DEBUG
      DebugConsole.emit(
        "card-management: refresh started; offersActivation=\(offersActivation) transport=\(transport)"
      )
    #endif
    nextRefreshIdentifier &+= 1
    let refreshIdentifier = nextRefreshIdentifier
    activeRefreshIdentifier = refreshIdentifier
    failure = nil
    notice = nil
    let result = await CardMaintenance.snapshot(
      transport: transport,
      cardAccessNumber: offeredCardAccessNumber
    )
    guard activeRefreshIdentifier == refreshIdentifier else { return }
    activeRefreshIdentifier = nil
    guard let result else {
      #if DEBUG
        DebugConsole.emit("card-management: refresh failed; clearing activation offer")
      #endif
      report = nil
      if !activationRequired {
        offersActivation = false
      }
      failure = unreadableCardMessage
      return
    }
    apply(result, preservingOutcome: false)
  }

  /// Removes feedback that belongs to the previously selected operation.
  internal func clearOutcome() {
    failure = nil
    notice = nil
  }

  internal func changePin1(current: String, new: String) async -> Bool {
    await perform(
      presenting: .pin1, spending: .pin1, accepted: String(localized: "PIN 1 changed.")
    ) {
      await CardMaintenance.changePin1(
        current: current,
        new: new,
        transport: transport,
        cardAccessNumber: offeredCardAccessNumber
      )
    }
  }

  internal func changePin2(current: String, new: String) async -> Bool {
    await perform(
      presenting: .pin2, spending: .pin2, accepted: String(localized: "PIN 2 changed.")
    ) {
      await CardMaintenance.changePin2(
        current: current,
        new: new,
        transport: transport,
        cardAccessNumber: offeredCardAccessNumber
      )
    }
  }

  internal func unblock(target: CredentialRole, puk: String, new: String) async -> Bool {
    let accepted =
      target == .pin2
      ? String(localized: "PIN 2 reset.")
      : String(localized: "PIN 1 reset.")
    return await perform(presenting: .puk, spending: .puk, accepted: accepted) {
      if target == .pin2 {
        return await CardMaintenance.unblockPin2(
          puk: puk,
          new: new,
          transport: transport,
          cardAccessNumber: offeredCardAccessNumber
        )
      }
      return await CardMaintenance.unblockPin1(
        puk: puk,
        new: new,
        transport: transport,
        cardAccessNumber: offeredCardAccessNumber
      )
    }
  }

  internal func activate(
    entry: String,
    newPin1: String?,
    newPin2: String?
  ) async -> Bool {
    guard beginCardOperation() else { return false }
    guard let scheme = activation?.scheme else {
      failure = String(localized: "The card could not be classified for activation.")
      return false
    }
    working = true
    failure = nil
    notice = nil
    let execution = await CardMaintenance.activate(
      request: CardMaintenance.ActivationRequest(
        entry: entry,
        newPin1: newPin1,
        newPin2: newPin2,
        scheme: scheme,
        needs: activationNeeds
      ),
      transport: transport,
      cardAccessNumber: offeredCardAccessNumber
    )
    working = false
    guard let execution else {
      failure = String(localized: "The card could not be classified for activation.")
      return false
    }
    _ = describe(execution.activation)
    activationNeeds = execution.remaining
    offersActivation = execution.remaining.any
    return !execution.remaining.any
  }

  internal func apply(
    _ snapshot: CardMaintenance.Snapshot,
    preservingOutcome: Bool
  ) {
    report = snapshot.report
    activation = snapshot.activation
    if let lengths = snapshot.pinLengths {
      pinLengths = lengths
    }
    if let needs = snapshot.activationNeeds {
      activationNeeds = needs
      offersActivation = needs.any
    } else {
      offersActivation = false
    }
    #if DEBUG
      DebugConsole.emit(
        "card-management: applied snapshot needs=\(String(describing: snapshot.activationNeeds)) "
          + "offersActivation=\(offersActivation)"
      )
    #endif
    if !preservingOutcome {
      failure = nil
      notice = nil
    }
  }

}
