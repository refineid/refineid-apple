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
      connect(accessNumber: "123456", pin1: "1234", in: app)

      fillSecure("managementActivationEntry", with: "1234567", in: app)
      fillSecure("managementActivationPin1", with: "4567", in: app)
      fillSecure("managementActivationPin1Repeat", with: "4567", in: app)
      fillSecure("managementActivationPin2", with: "654321", in: app)
      fillSecure("managementActivationPin2Repeat", with: "654321", in: app)
      commit(action: UITestIdentifiers.managementActivate, in: app)

      let pin1 = app.secureTextFields[UITestIdentifiers.pin1Field]
      guard pin1.waitForExistence(timeout: UITestApp.appearTimeout) else {
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
      XCTAssertEqual(
        pin1.value as? String,
        "Basic Code (PIN 1)",
        "PIN 1 entered before factory-card classification was retained")
    }

    internal func testCardAccessNumberAcceptsDirectGUIInput() {
      let app = UITestApp.launchVirtualCard()
      let field = app.textFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      focusAndType(field, value: "123456", in: app)
      XCTAssertEqual(
        app.textFields[UITestIdentifiers.cardAccessNumberField].value as? String,
        "123456")
    }

    internal func testWirelessManagementRequiresLiveCardClassification() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)
      let signing = app.buttons[UITestIdentifiers.signDocuments]
      let key = app.buttons[UITestIdentifiers.pinManagementButton]

      XCTAssertTrue(
        signing.waitForExistence(timeout: UITestApp.appearTimeout),
        "wireless setup hid document signing instead of presenting it disabled")
      XCTAssertFalse(
        signing.isEnabled,
        "document signing was enabled before CAN was complete")
      XCTAssertEqual(signing.label, "Sign")
      XCTAssertTrue(app.staticTexts["Document"].exists)
      XCTAssertTrue(key.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(key.isEnabled, "PIN management was enabled before CAN was complete")

      let cache = app.buttons[UITestIdentifiers.primeStartButton]
      XCTAssertTrue(cache.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertEqual(cache.label, "Cache")
      let cardHeader = app.staticTexts["Card"]
      let documentHeader = app.staticTexts["Document"]
      XCTAssertTrue(cardHeader.exists)
      XCTAssertEqual(cardHeader.frame.minX, documentHeader.frame.minX, accuracy: 1)

      let can = app.textFields[UITestIdentifiers.cardAccessNumberField]
      let pin1 = app.secureTextFields[UITestIdentifiers.pin1Field]
      XCTAssertTrue(can.exists)
      XCTAssertTrue(pin1.exists)
      XCTAssertEqual(can.frame.height, pin1.frame.height, accuracy: 1)

      focusAndType(can, value: "123456", in: app)
      let signingEnabled = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "enabled == true"),
        object: signing)
      let keyEnabled = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "enabled == true"),
        object: key)
      XCTAssertEqual(
        XCTWaiter.wait(
          for: [signingEnabled, keyEnabled],
          timeout: UITestApp.appearTimeout),
        .completed,
        "six-digit CAN did not enable signing and PIN management")

      openManagement(in: app)
    }

    internal func testActivatedNFCCardRevealsAuthenticationThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)

      XCTAssertTrue(
        app.secureTextFields[UITestIdentifiers.pin1Field]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "initial setup did not offer PIN 1 with CAN")
      connect(accessNumber: "123456", pin1: "1234", in: app)

      XCTAssertTrue(
        app.staticTexts["Identity"]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "activated card did not continue directly through authentication")
      XCTAssertTrue(
        app.buttons[UITestIdentifiers.signDocuments]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "validated NFC card did not reveal document signing")
    }

    internal func testWrongCardAccessNumberReturnsToSetupThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)
      connect(accessNumber: "654321", pin1: "1234", in: app)

      let field = app.textFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertEqual(field.value as? String, "Card Access Number (CAN)")
      XCTAssertTrue(
        app.staticTexts["The Card Access Number (CAN) is incorrect."]
          .waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(app.buttons[UITestIdentifiers.managementActivate].exists)
    }

    internal func testConnectionFailureKeepsTransientCardAccessNumber() {
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
      connect(accessNumber: "123456", pin1: "1234", in: app)

      XCTAssertEqual(
        app.textFields[UITestIdentifiers.cardAccessNumberField].value as? String,
        "123456")
      XCTAssertTrue(
        app.staticTexts["The identity card could not be read. Try again."]
          .waitForExistence(timeout: UITestApp.appearTimeout))
    }

    internal func testPartialActivationRequestsOnlyPIN2ThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("partial-activation-nfc", in: app)

      connect(accessNumber: "123456", pin1: "1234", in: app)

      XCTAssertTrue(
        app.secureTextFields["managementActivationPin2"]
          .waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(app.secureTextFields["managementActivationPin1"].exists)
    }
  }
#endif
