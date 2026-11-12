// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// Activating and managing the virtual card through the visible GUI.
  @MainActor
  internal final class VirtualIDCardActivationUITests: XCTestCase {
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

    internal func testFactoryFreshNFCCardActivatesThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("factory-fresh-nfc", in: app)
      connect(accessNumber: "123456", in: app)

      fillSecure("managementActivationEntry", with: "1234567", in: app)
      fillSecure("managementActivationPin1", with: "4567", in: app)
      fillSecure("managementActivationPin1Repeat", with: "4567", in: app)
      fillSecure("managementActivationPin2", with: "654321", in: app)
      fillSecure("managementActivationPin2Repeat", with: "654321", in: app)
      commit(action: UITestIdentifiers.managementActivate, in: app)

      let setupActions = app.buttons[UITestIdentifiers.setupAuthenticate]
      guard setupActions.waitForExistence(timeout: UITestApp.appearTimeout) else {
        let visibleFeedback = app.staticTexts.allElementsBoundByIndex
          .map(\.label)
          .filter { !$0.isEmpty }
          .joined(separator: " | ")
        openEditor(in: app)
        let pin1Factory = app.switches["virtualCardPIN1Factory"]
        let pin2Factory = app.switches["virtualCardPIN2Factory"]
        scrollTo(pin1Factory, in: app)
        XCTAssertTrue(pin1Factory.waitForExistence(timeout: UITestApp.appearTimeout))
        XCTAssertTrue(pin2Factory.waitForExistence(timeout: UITestApp.appearTimeout))
        XCTFail(
          "successful activation did not reveal authentication; "
            + "feedback=\(visibleFeedback); "
            + "PIN 1 factory=\(String(describing: pin1Factory.value)), "
            + "PIN 2 factory=\(String(describing: pin2Factory.value))")
        return
      }
    }

    internal func testCardAccessNumberAcceptsDirectGUIInput() {
      let app = UITestApp.launchVirtualCard()
      let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
      XCTAssertTrue(auth.waitForExistence(timeout: UITestApp.appearTimeout))
      auth.tap()
      let field = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      focusAndType(field, value: "12345", in: app)
      XCTAssertEqual(
        app.secureTextFields[UITestIdentifiers.cardAccessNumberField].value as? String,
        "12345")
    }

    internal func testWirelessSetupOffersItsThreeActionsUpFront() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)

      for action in [
        UITestIdentifiers.verifyDocuments,
        UITestIdentifiers.signDocuments,
        UITestIdentifiers.setupAuthenticate,
      ] {
        let button = app.buttons[action]
        XCTAssertTrue(
          button.waitForExistence(timeout: UITestApp.appearTimeout),
          "wireless setup hid \(action)")
        XCTAssertTrue(button.isEnabled, "\(action) is not offered up front")
      }
      XCTAssertFalse(
        app.buttons[UITestIdentifiers.pinManagementButton].exists,
        "PIN management is offered before any identity exists")
      XCTAssertFalse(
        app.secureTextFields[UITestIdentifiers.cardAccessNumberField].exists,
        "setup asks for the CAN before it is needed")

      let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
      auth.tap()
      let can = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(can.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(
        app.secureTextFields[UITestIdentifiers.pin1Field].exists,
        "setup asks for no PIN")
      XCTAssertFalse(
        app.buttons[UITestIdentifiers.primeStartButton].exists,
        "personal setup keeps a start button")

      focusAndType(can, value: "123456", in: app)
      let dismissed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"),
        object: can)
      XCTAssertEqual(
        XCTWaiter.wait(for: [dismissed], timeout: UITestApp.appearTimeout),
        .completed,
        "a complete entry did not start the hold by itself")
    }

    internal func testActivatedNFCCardRevealsAuthenticationThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)

      XCTAssertTrue(
        app.buttons[UITestIdentifiers.setupAuthenticate]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "initial setup did not offer authentication")
      connect(accessNumber: "123456", in: app)

      XCTAssertTrue(
        app.staticTexts["Identity"]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "activated card did not continue directly through authentication")
      XCTAssertTrue(
        app.buttons[UITestIdentifiers.signDocuments]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "validated NFC card did not reveal document signing")
    }

    internal func testCompleteEntryStartsTheHoldWithoutATapThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)

      let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
      XCTAssertTrue(auth.waitForExistence(timeout: UITestApp.appearTimeout))
      auth.tap()
      let field = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      focusAndType(field, value: "123456", in: app)

      let dismissed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"),
        object: field)
      XCTAssertEqual(
        XCTWaiter.wait(for: [dismissed], timeout: UITestApp.appearTimeout),
        .completed,
        "a complete entry did not start the hold by itself")
      XCTAssertTrue(
        app.staticTexts[UITestIdentifiers.identityStatus]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "the automatically started hold registered no identity")
    }

    internal func testWrongCardAccessNumberReturnsToSetupThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)
      connect(accessNumber: "654321", in: app)

      let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
      XCTAssertTrue(auth.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertTrue(
        app.staticTexts["The Card Access Number (CAN) is incorrect."]
          .waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(app.buttons[UITestIdentifiers.managementActivate].exists)
      auth.tap()

      let field = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertNotEqual(
        field.value as? String,
        "654321",
        "the incorrect entry was kept for the retry")
    }

    internal func testConnectionFailureOpensAFreshRetryThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      openEditor(in: app)
      selectMenu(
        identifier: UITestIdentifiers.virtualCardScenario,
        option: "activated-nfc",
        in: app,
        optionIdentifier: "virtualCardScenarioOption.activated-nfc")
      selectMenu(
        identifier: UITestIdentifiers.virtualCardFault,
        option: "nfcDisconnectBeforeConnection",
        in: app,
        optionIdentifier:
          "virtualCardFaultOption.nfcDisconnectBeforeConnection",
        scrolling: true)
      applyEditor(in: app)
      connect(accessNumber: "123456", in: app)

      let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
      XCTAssertTrue(auth.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertTrue(
        app.staticTexts["The identity card could not be read. Try again."]
          .waitForExistence(timeout: UITestApp.appearTimeout))
      auth.tap()

      let field = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertNotEqual(
        field.value as? String,
        "123456",
        "the failed entry was kept instead of opening empty")
    }

    internal func testPartialActivationRequestsOnlyPIN2ThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("partial-activation-nfc", in: app)

      connect(accessNumber: "123456", in: app)

      XCTAssertTrue(
        app.secureTextFields["managementActivationPin2"]
          .waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(app.secureTextFields["managementActivationPin1"].exists)
    }
  }
#endif
