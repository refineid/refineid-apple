// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)

  import CardCore
  import Foundation
  import SwiftUI
  #if os(iOS)
    import UIKit
  #elseif os(macOS)
    import AppKit
  #endif

  /// Process-scoped demonstration and UI-test environment.
  ///
  /// The environment owns an explicit VirtualIDCard. It never falls through to
  /// physical card I/O, Keychain storage, token registration, or production
  /// diagnostics. Quitting the process destroys both its card and device state.
  @MainActor
  internal final class DemoMode: ObservableObject {
    // MARK: Static Properties

    internal static let shared = DemoMode()

    internal static let launchArgument = "--virtual-card"

    /// A demonstration fakes the antenna, never the device class: only
    /// an iPhone is offered near-field states.
    #if os(iOS)
      internal static let offersNearField =
        UIDevice.current.userInterfaceIdiom == .phone
    #else
      internal static let offersNearField = false
    #endif

    // MARK: Static Computed Properties

    /// The scenario a demonstration starts from on this device class.
    ///
    /// A demonstration walks only the flows the build offers. With
    /// activation shipping, the card arrives factory fresh so the whole
    /// journey can be shown; with activation gated, it arrives already
    /// activated - exactly like the card of a holder who activated it
    /// elsewhere - so the demonstration starts where the product does.
    internal static var defaultScenario: VirtualIDCard.Scenario {
      #if FEATURE_CARD_ACTIVATION
        offersNearField ? .factoryFreshNearField : .factoryFreshReader
      #else
        offersNearField ? .activatedNearField : .activatedReader
      #endif
    }

    // MARK: Properties

    @Published internal private(set) var isActive = false
    @Published internal private(set) var state = DemoMode.defaultScenario.snapshot
    @Published internal private(set) var revision = 0
    @Published internal private(set) var isEditorPresented = false

    private var card = VirtualIDCard(scenario: DemoMode.defaultScenario)

    // MARK: Computed Properties

    internal var isHolding: Bool { false }

    internal var hasIdentity: Bool {
      state.device.cachedIdentity && state.device.tokenRegistered
    }

    internal var holderName: String {
      let raw = state.card.holderName
      return Bundle.main.localizedString(forKey: raw, value: nil, table: nil)
    }

    internal var hasValidatedConnection: Bool {
      state.device.connectedCardAccessNumber != nil
        || state.device.storedCardAccessNumber != nil
    }

    internal var displayedCardAccessNumber: String? {
      state.device.storedCardAccessNumber
        ?? state.device.connectedCardAccessNumber
    }

    internal var isReaderCardPresent: Bool {
      state.card.transport == .reader
        && state.card.readerConnected
        && state.card.cardPresent
    }

    internal var activationNeeds: CardActivationNeeds {
      CardActivationNeeds(
        pin1: state.card.pin1.isFactoryValue,
        pin2: state.card.pin2.isFactoryValue)
    }

    internal var activationScheme: ActivationScheme {
      Self.scheme(for: state.card.generation)
    }

    // MARK: Functions

    internal func setEditorPresented(_ presented: Bool) {
      isEditorPresented = presented
    }

    internal func activate(
      scenario: VirtualIDCard.Scenario
    ) {
      isActive = true
      state = scenario.snapshot
      card = VirtualIDCard(snapshot: state)
      publishState()
    }

    internal func deactivate() {
      isActive = false
      state = Self.defaultScenario.snapshot
      card = VirtualIDCard(scenario: Self.defaultScenario)
      publishState()
    }

    #if DEBUG
      internal func activateFromLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        guard
          let flag = arguments.firstIndex(of: Self.launchArgument),
          arguments.index(after: flag) < arguments.endIndex,
          let scenario = VirtualIDCard.Scenario(
            rawValue: arguments[arguments.index(after: flag)])
        else {
          return
        }
        activate(scenario: scenario)
      }
    #endif

    internal func replace(with snapshot: VirtualIDCard.Snapshot) {
      state = snapshot
      card = VirtualIDCard(snapshot: snapshot)
      publishState()
    }

    internal func reset(to scenario: VirtualIDCard.Scenario) {
      state = scenario.snapshot
      card = VirtualIDCard(snapshot: state)
      publishState()
    }

    internal func forgetIdentity() {
      state.device = VirtualIDCard.DeviceState()
      card = VirtualIDCard(snapshot: state)
      publishState()
    }

    internal func connectionSnapshot(
      cardAccessNumber: String
    ) async -> CardMaintenance.ConnectionSnapshotResult {
      let result = await card.connect(cardAccessNumber: cardAccessNumber)
      let latest = await synchronizeFromCard()
      switch result {
      case .connected:
        return .connected(Self.maintenanceSnapshot(from: latest, retryReport: nil, report: nil))

      case .incorrectCardAccessNumber:
        return .wrongCardAccessNumber

      case .unavailable:
        return .failed
      }
    }

    internal func maintenanceSnapshot() async -> CardMaintenance.Snapshot? {
      let probe = await card.probeCredentials()
      let latest = await synchronizeFromCard()
      switch probe {
      case .report(let report):
        return Self.maintenanceSnapshot(from: latest, retryReport: report, report: nil)

      case .unreadable:
        return Self.maintenanceSnapshot(
          from: latest,
          retryReport: nil,
          report: CredentialProbeReport(
            pin1: .noInformation,
            pin2: .noInformation,
            puk: .noInformation))

      case .unavailable:
        return nil
      }
    }

    internal func credentialReport() async -> CredentialProbeReport? {
      let probe = await card.probeCredentials()
      _ = await synchronizeFromCard()
      switch probe {
      case .report(let report):
        return Self.report(from: report)

      case .unreadable:
        return CredentialProbeReport(
          pin1: .noInformation,
          pin2: .noInformation,
          puk: .noInformation)

      case .unavailable:
        return nil
      }
    }

    internal func readerActivationScheme() -> ActivationScheme? {
      guard isReaderCardPresent else { return nil }
      return activationScheme
    }

    internal func changePIN1(
      current: String,
      new: String
    ) async -> CardMaintenance.MutationReport {
      await mutation(await card.changePIN1(current: current, new: new))
    }

    internal func changePIN2(
      current: String,
      new: String
    ) async -> CardMaintenance.MutationReport {
      await mutation(await card.changePIN2(current: current, new: new))
    }

    internal func resetPIN1(
      puk: String,
      new: String
    ) async -> CardMaintenance.MutationReport {
      await mutation(await card.resetPIN1(puk: puk, new: new))
    }

    internal func resetPIN2(
      puk: String,
      new: String
    ) async -> CardMaintenance.MutationReport {
      await mutation(await card.resetPIN2(puk: puk, new: new))
    }

    internal func activateCard(
      request: CardMaintenance.ActivationRequest
    ) async -> CardMaintenance.ActivationExecution {
      let result = await card.activate(
        VirtualIDCard.ActivationRequest(
          entry: request.entry,
          newPIN1: request.newPin1,
          newPIN2: request.newPin2))
      let latest = await synchronizeFromCard()
      return CardMaintenance.ActivationExecution(
        activation: CardMaintenance.ActivationReport(
          scheme: Self.scheme(for: latest.card.generation),
          pin1: Self.outcome(from: result.pin1),
          pin2: result.pin2.map(Self.outcome(from:))),
        remaining: CardActivationNeeds(
          pin1: latest.card.pin1.isFactoryValue,
          pin2: latest.card.pin2.isFactoryValue))
    }

    internal func authenticate(
      pin1: String
    ) async -> VirtualIDCard.AuthenticationResult {
      let result = await card.authenticate(pin1: pin1)
      _ = await synchronizeFromCard()
      return result
    }

    internal func authorizeQualifiedSignature(
      pin2: String
    ) async -> VirtualIDCard.SignatureResult {
      let result = await card.authorizeQualifiedSignature(pin2: pin2)
      _ = await synchronizeFromCard()
      return result
    }

    private func mutation(
      _ result: VirtualIDCard.MutationResult
    ) async -> CardMaintenance.MutationReport {
      let latest = await synchronizeFromCard()
      let outcome = Self.outcome(from: result.outcome)
      let snapshot: CardMaintenance.Snapshot?
      if case .transportFailure = result.outcome {
        snapshot = nil
      } else {
        snapshot = Self.maintenanceSnapshot(from: latest, retryReport: nil, report: nil)
      }
      return CardMaintenance.MutationReport(
        outcome: outcome,
        snapshot: snapshot)
    }

    @discardableResult
    private func synchronizeFromCard() async -> VirtualIDCard.Snapshot {
      let latest = await card.inspect()
      state = latest
      publishState()
      return latest
    }

    private func publishState() {
      revision &+= 1
      if state.card.cardPresent, !activationNeeds.any {
        CredentialRetryHealth.shared.update(
          Self.report(from: state.card))
      } else {
        CredentialRetryHealth.shared.clear()
      }
    }
  }

#endif
