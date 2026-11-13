// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// The setup actions in one journey: signing opens and closes, then
  /// authentication prompts, starts its own hold, and registers.
  ///
  /// The signing leg guards the navigation, not the signature: leaving
  /// the signing screen must return to setup, never re-present signing
  /// over whatever opens next.
  @MainActor
  internal final class SetupActionsJourneyUITests: XCTestCase {
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

    #if FEATURE_ORGANIZATION_CARD
      internal func testOrganizationModeLabelsItsCredentialAndOmitsCanFromSigning() {
        let app = UITestApp.launch(
          arguments: ["--virtual-card", "absent", "-organizationCardEnabled", "YES"])
        applyScenario("activated-nfc", in: app)
        let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
        XCTAssertTrue(auth.waitForExistence(timeout: UITestApp.appearTimeout))
        auth.tap()
        let field = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
        XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
        XCTAssertTrue(app.buttons[UITestIdentifiers.primeStartButton].exists)
        XCTAssertTrue(field.label.contains("PIN 1"))
        app.navigationBars.buttons.firstMatch.tap()
        openEditor(in: app)
        let pending = app.buttons["virtualCardSigningPending"]
        scrollTo(pending, in: app)
        XCTAssertTrue(pending.waitForExistence(timeout: UITestApp.appearTimeout))
        pending.tap()
        applyEditor(in: app)
        app.buttons[UITestIdentifiers.signDocuments].tap()
        XCTAssertTrue(
          app.secureTextFields["signingPIN2"].waitForExistence(timeout: UITestApp.appearTimeout))
        XCTAssertFalse(app.secureTextFields["signingCardAccessNumber"].exists)
      }

    #else
      /// A stale organization switch from an earlier build must not
      /// switch the entry to an organization PIN 1 in a build without
      /// organization-card support.
      internal func testStaleOrganizationSwitchShowsCardAccessNumberEntry() {
        let app = UITestApp.launch(
          arguments: ["--virtual-card", "absent", "-organizationCardEnabled", "YES"])
        applyScenario("activated-nfc", in: app)
        let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
        XCTAssertTrue(auth.waitForExistence(timeout: UITestApp.appearTimeout))
        auth.tap()
        let field = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
        XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
        XCTAssertFalse(field.label.contains("PIN 1"))
      }
    #endif

    internal func testSignBackThenAuthenticateReachesIdentityThroughGUI() {
      let app = UITestApp.launch(arguments: [
        "--virtual-card", "absent", "-organizationCardEnabled", "NO",
      ])
      applyScenario("activated-nfc", in: app)

      let sign = app.buttons[UITestIdentifiers.signDocuments]
      XCTAssertTrue(sign.waitForExistence(timeout: UITestApp.appearTimeout))
      sign.tap()
      XCTAssertTrue(
        app.buttons["signingChooseDocuments"]
          .waitForExistence(timeout: UITestApp.appearTimeout))
      app.navigationBars.buttons.firstMatch.tap()

      let auth = app.buttons[UITestIdentifiers.setupAuthenticate]
      XCTAssertTrue(
        auth.waitForExistence(timeout: UITestApp.appearTimeout),
        "leaving signing did not return to the setup actions")
      auth.tap()
      let field = app.secureTextFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(
        field.waitForExistence(timeout: UITestApp.appearTimeout),
        "authentication did not prompt for the CAN")
      focusAndType(field, value: "123456", in: app)
      XCTAssertTrue(
        app.staticTexts[UITestIdentifiers.identityStatus]
          .waitForExistence(timeout: 60),
        "the hold registered no identity")
    }
  }

#endif
