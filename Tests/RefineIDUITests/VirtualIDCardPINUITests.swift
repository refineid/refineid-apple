// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// PIN changes, resets and recovery through the visible GUI.
  @MainActor
  internal final class VirtualIDCardPINUITests: XCTestCase {
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

    internal func testChangePIN1RunsThroughGUI() {
      assertCredentialJourney(
        VirtualIDCardUITestSupport.CredentialJourney(
          task: "Change PIN 1",
          fields: [
            ("managementChangePIN1Current", "1234"),
            ("managementChangePIN1New", "9876"),
            ("managementChangePIN1Repeat", "9876"),
          ],
          action: UITestIdentifiers.managementChangePin1,
          outcome: "PIN 1 changed"))
    }

    internal func testChangePIN2RunsThroughGUI() {
      assertCredentialJourney(
        VirtualIDCardUITestSupport.CredentialJourney(
          task: "Change PIN 2",
          fields: [
            ("managementChangePIN2Current", "123456"),
            ("managementChangePIN2New", "987654"),
            ("managementChangePIN2Repeat", "987654"),
          ],
          action: UITestIdentifiers.managementChangePin2,
          outcome: "PIN 2 changed"))
    }

    internal func testResetPIN1RunsThroughGUI() {
      assertCredentialJourney(
        VirtualIDCardUITestSupport.CredentialJourney(
          task: "Reset PIN 1",
          fields: [
            ("managementResetPIN1Puk", "12345678"),
            ("managementResetPIN1New", "9876"),
            ("managementResetPIN1Repeat", "9876"),
          ],
          action: UITestIdentifiers.managementResetPin1,
          outcome: "PIN 1 reset"))
    }

    internal func testResetPIN2RunsThroughGUI() {
      assertCredentialJourney(
        VirtualIDCardUITestSupport.CredentialJourney(
          task: "Reset PIN 2",
          fields: [
            ("managementResetPIN2Puk", "12345678"),
            ("managementResetPIN2New", "987654"),
            ("managementResetPIN2Repeat", "987654"),
          ],
          action: UITestIdentifiers.managementResetPin2,
          outcome: "PIN 2 reset"))
    }

    internal func testRetryCounterEditedInGUISelectsRecovery() {
      let app = UITestApp.launchVirtualCard()
      openEditor(in: app)
      selectMenu(
        identifier: UITestIdentifiers.virtualCardScenario,
        option: "activated-reader",
        in: app,
        optionIdentifier: "virtualCardScenarioOption.activated-reader")
      let stepper = app.steppers[UITestIdentifiers.virtualCardPIN1Attempts]
      scrollTo(stepper, in: app)
      XCTAssertTrue(stepper.waitForExistence(timeout: UITestApp.appearTimeout))
      let decrement = stepper.buttons.firstMatch
      XCTAssertTrue(decrement.exists)
      decrement.tap()
      decrement.tap()
      decrement.tap()
      applyEditor(in: app)

      openManagement(in: app)

      XCTAssertTrue(
        app.buttons["Reset PIN 1"].firstMatch
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "a PIN 1 retry floor did not select PIN 1 recovery")
    }
  }
#endif
