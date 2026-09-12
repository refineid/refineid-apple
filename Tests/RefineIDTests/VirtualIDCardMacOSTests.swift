// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import Foundation
  import Testing

  @testable import RefineID

  /// Proves that the Virtual ID Card test harness functions completely on macOS
  /// without requiring physical card readers or smart card tokens.
  @Suite(.serialized)
  internal struct VirtualIDCardMacOSTests {
    @Test
    @MainActor
    internal func demoModePlatformPropertiesOnMacOS() {
      #expect(DemoMode.offersNearField == false)
      #if FEATURE_CARD_ACTIVATION
        #expect(DemoMode.defaultScenario == .factoryFreshReader)
      #else
        #expect(DemoMode.defaultScenario == .activatedReader)
      #endif
    }

    @Test
    @MainActor
    internal func demoModeActivationAndDeactivation() {
      let demo = DemoMode.shared
      demo.deactivate()
      #expect(demo.isActive == false)

      demo.activate(scenario: .activatedReader)
      #expect(demo.isActive == true)
      #expect(demo.isReaderCardPresent == true)
      #expect(demo.holderName == "DOE JANE 12345678N")
      #expect(demo.hasIdentity == false)

      demo.activate(scenario: .registeredNearField)
      #expect(demo.hasIdentity == true)

      demo.deactivate()
      #expect(demo.isActive == false)
    }

    @Test
    @MainActor
    internal func virtualCardMaintenanceCredentialReport() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .activatedReader)
      defer { demo.deactivate() }

      let report = await CardMaintenance.credentialReport(
        transport: .reader,
        cardAccessNumber: nil
      )
      #expect(report != nil)
      if let report {
        guard let five = RetryCount(attemptsRemaining: 5) else {
          Issue.record("RetryCount failed to initialize")
          return
        }
        #expect(report.pin1 == .remaining(five))
        #expect(report.pin2 == .remaining(five))
        #expect(report.puk == .remaining(five))
      }
    }

    @Test
    @MainActor
    internal func virtualCardMaintenancePINChangesAndResets() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .activatedReader)
      defer { demo.deactivate() }

      // Change PIN 1
      let changeResult = await CardMaintenance.changePin1(
        current: "1234",
        new: "5678",
        transport: .reader,
        cardAccessNumber: nil
      )
      #expect(changeResult.outcome == .success)
      #expect(demo.state.card.pin1.value == "5678")

      // Wrong PIN 1 attempt decrements counter
      let wrongResult = await CardMaintenance.changePin1(
        current: "0000",
        new: "1111",
        transport: .reader,
        cardAccessNumber: nil
      )
      guard let four = RetryCount(attemptsRemaining: 4) else {
        Issue.record("RetryCount failed to initialize")
        return
      }
      #expect(wrongResult.outcome == .rejected(remaining: four))
      #expect(demo.state.card.pin1.attemptsRemaining == 4)

      // Reset PIN 1 with PUK
      let resetResult = await CardMaintenance.unblockPin1(
        puk: "12345678",
        new: "4321",
        transport: .reader,
        cardAccessNumber: nil
      )
      #expect(resetResult.outcome == .success)
      #expect(demo.state.card.pin1.value == "4321")
      #expect(demo.state.card.pin1.attemptsRemaining == 5)
    }

    @Test
    @MainActor
    internal func virtualCardActivationWatchStateMachine() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .factoryFreshReader)
      defer { demo.deactivate() }

      #expect(demo.activationNeeds.any == true)
      let watch = ActivationWatch()
      watch.observe(
        availability: .noCard,
        paused: false,
        identity: LoginIdentityModel.shared
      )
      #expect(watch.awaitsActivation == true)

      // Perform activation
      let execution = await CardMaintenance.activate(
        request: CardMaintenance.ActivationRequest(
          entry: "1234567",
          newPin1: "1234",
          newPin2: "123456",
          scheme: demo.activationScheme,
          needs: demo.activationNeeds
        ),
        transport: .reader,
        cardAccessNumber: nil
      )
      #expect(execution != nil)
      #expect(execution?.activation.pin1 == .success)
      #expect(execution?.activation.pin2 == .success)
      #expect(demo.activationNeeds.any == false)

      // Observe updated state
      watch.observe(
        availability: .ready,
        paused: false,
        identity: LoginIdentityModel.shared
      )
      #expect(watch.awaitsActivation == false)
    }

    @Test
    @MainActor
    internal func virtualCardDocumentSigningSuccessAndFailure() async throws {
      let demo = DemoMode.shared
      demo.activate(scenario: .activatedReader)
      defer { demo.deactivate() }

      let signing = SignDocumentModel()
      let tempDir = FileManager.default.temporaryDirectory
      let sourceURL = tempDir.appendingPathComponent("TestVirtualSign-\(UUID().uuidString).pdf")
      let destURL = tempDir.appendingPathComponent("TestVirtualSigned-\(UUID().uuidString).pdf")
      let fakeData = Data("%PDF-1.4\n% Test\n%%EOF".utf8)
      try fakeData.write(to: sourceURL)
      defer {
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: destURL)
      }

      signing.accept(sourceURL)
      #expect(signing.pending == sourceURL)

      // Wrong PIN 2
      await signing.sign(
        pin2: "000000",
        accessNumber: "",
        format: .pades,
        to: destURL
      )
      #expect(signing.failure != nil)
      #expect(signing.signed == nil)
      #expect(demo.state.card.pin2.attemptsRemaining == 4)

      // Correct PIN 2 ("123456" default in activatedReader)
      await signing.sign(
        pin2: "123456",
        accessNumber: "",
        format: .pades,
        to: destURL
      )
      #expect(signing.failure == nil)
      #expect(signing.signed == destURL)
      #expect(FileManager.default.fileExists(atPath: destURL.path) == true)
    }

    @Test
    @MainActor
    internal func virtualCardLocalizationKeysExist() {
      let scenarioName = VirtualIDCard.Scenario.activatedReader.localizedName
      #expect(!scenarioName.isEmpty)

      let faultName = VirtualIDCard.FaultPreset.noFault.localizedName
      #expect(!faultName.isEmpty)

      let title = virtualCardLocalized("title", defaultValue: "Virtual ID Card")
      #expect(title == "Virtual ID Card")
    }

    @Test
    @MainActor
    internal func virtualCardSettingsAndManagementIntegration() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .activatedReader)
      defer { demo.deactivate() }

      let management = CardManagementModel(
        transport: .reader,
        activationRequired: false,
        cardAccessNumber: nil,
        activationScheme: nil,
        activationNeeds: nil
      )
      await management.refresh()
      #expect(management.report != nil)
      if let report = management.report {
        guard let five = RetryCount(attemptsRemaining: 5) else {
          Issue.record("RetryCount failed to initialize")
          return
        }
        #expect(report.pin1 == .remaining(five))
        #expect(report.pin2 == .remaining(five))
      }

      // Test changing PIN 1 through the management model
      let changed = await management.changePin1(current: "1234", new: "4321")
      #expect(changed == true)
      #expect(demo.state.card.pin1.value == "4321")
    }
  }

#endif
