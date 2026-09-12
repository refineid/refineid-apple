// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// Hardware-free journeys configured through the visible Virtual ID Card.
  @MainActor
  internal final class VirtualIDCardUITests: XCTestCase {
    override internal func setUp() {
      super.setUp()
      continueAfterFailure = false
    }

    override internal func tearDown() {
      MainActor.assumeIsolated {
        XCUIApplication().terminate()
      }
      continueAfterFailure = true
      super.tearDown()
    }

    internal func testScenarioFactoryFreshNFCRoutesThroughGUI() {
      assertScenario("factory-fresh-nfc", destination: .cardAccessNumber)
    }

    internal func testScenarioLegacyFactoryFreshNFCRoutesThroughGUI() {
      assertScenario("legacy-factory-fresh-nfc", destination: .cardAccessNumber)
    }

    internal func testScenarioPartialActivationNFCRoutesThroughGUI() {
      assertScenario("partial-activation-nfc", destination: .cardAccessNumber)
    }

    internal func testScenarioActivatedNFCRoutesThroughGUI() {
      assertScenario("activated-nfc", destination: .cardAccessNumber)
    }

    internal func testScenarioRegisteredNFCRoutesThroughGUI() {
      assertScenario("registered-nfc", destination: .registeredIdentity)
    }

    internal func testRegisteredNFCCardClassifiesAndReturnsToIdentityThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("registered-nfc", in: app)

      let identity = app.staticTexts[UITestIdentifiers.identityStatus]
      XCTAssertTrue(identity.waitForExistence(timeout: UITestApp.appearTimeout))
      openManagement(in: app)

      let back = app.navigationBars.buttons.firstMatch
      XCTAssertTrue(back.waitForExistence(timeout: UITestApp.appearTimeout))
      back.tap()
      XCTAssertTrue(
        identity.waitForExistence(timeout: UITestApp.appearTimeout),
        "dismissing PIN management lost the registered identity origin")
    }

    internal func testScenarioFactoryFreshReaderRoutesThroughGUI() {
      assertScenario("factory-fresh-reader", destination: .activation)
    }

    internal func testScenarioActivatedReaderRoutesThroughGUI() {
      assertScenario("activated-reader", destination: .readerIdentity)
    }

    internal func testScenarioPIN1RecoveryReaderRoutesThroughGUI() {
      assertScenario("pin1-recovery-reader", destination: .readerIdentity)
    }

    internal func testScenarioPIN2RecoveryReaderRoutesThroughGUI() {
      assertScenario("pin2-recovery-reader", destination: .readerIdentity)
    }

    internal func testScenarioPUKRecoveryRefusedReaderRoutesThroughGUI() {
      assertScenario("puk-recovery-refused-reader", destination: .readerIdentity)
    }

    internal func testScenarioAbsentCardRoutesThroughGUI() {
      assertScenario("absent", destination: .cardAccessNumber)
    }

    internal func testFaultPresetNoFaultIsConfiguredThroughGUI() {
      assertFaultPreset("noFault")
    }

    internal func testFaultPresetNFCDisconnectIsConfiguredThroughGUI() {
      assertFaultPreset("nfcDisconnectBeforeConnection")
    }

    internal func testFaultPresetReaderCounterFailureIsConfiguredThroughGUI() {
      assertFaultPreset("readerFailsCounterQuery")
    }

    internal func testFaultPresetCardRemovalDuringPINChangeIsConfiguredThroughGUI() {
      assertFaultPreset("cardRemovedDuringPINChange")
    }

    internal func testFaultPresetLostPIN1ActivationResponseIsConfiguredThroughGUI() {
      assertFaultPreset("responseLostAfterPIN1Activation")
    }

    internal func testFaultPresetLostPIN2ActivationResponseIsConfiguredThroughGUI() {
      assertFaultPreset("responseLostAfterPIN2Activation")
    }

    internal func testFaultPresetCertificateReadFailureIsConfiguredThroughGUI() {
      assertFaultPreset("certificateReadFailure")
    }

    internal func testFaultPresetTokenPublicationFailureIsConfiguredThroughGUI() {
      assertFaultPreset("tokenPublicationFailure")
    }

    internal func testFaultPresetCardRemovalDuringSignatureIsConfiguredThroughGUI() {
      assertFaultPreset("cardRemovedDuringSignature")
    }

    internal func testFaultPresetLostSignatureResponseIsConfiguredThroughGUI() {
      assertFaultPreset("responseLostAfterSignature")
    }

    /// The audit arrived after the oldest system this app runs on, so
    /// this check is offered only where it exists.
  }
#endif
