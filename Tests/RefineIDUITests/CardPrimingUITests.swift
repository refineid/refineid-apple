// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// One setup run, keeping the card in place through the two system NFC
  /// fields, ending in a card the system can ask for.
  ///
  /// The holder-facing screen deliberately contains no progress or result
  /// report. The test therefore verifies the persistent CryptoTokenKit
  /// registration through the app's diagnostic report.
  ///
  /// The card must be resting on the phone before the run and stay there.
  /// The test brings the device's credentials up to date first when the
  /// environment carries them, so it does not depend on the setup test
  /// having run before it: XCTest promises no ordering between classes, and
  /// a device round trip is too expensive to spend learning that.
  @MainActor
  internal final class CardPrimingUITests: XCTestCase {
    // MARK: Static Properties

    /// How long the two-field setup takes: Core NFC PACE and metadata reads,
    /// followed by the live CryptoTokenKit registration field.
    private static let primeTimeout: TimeInterval = 180

    /// How long a screen takes to appear after a tap.
    private static let appearTimeout: TimeInterval = 15

    // MARK: Static Functions

    /// Brings the device's stored credentials up to date when the run was
    /// given them.
    ///
    /// Silent when it was not: a device that is already set up is a
    /// perfectly good subject for a priming run, and refusing to prime it
    /// would make this test unusable for the case it is most often wanted
    /// in.
    private static func storeCredentialsIfGiven(in app: XCUIApplication) {
      _ = CardSetupScreen.enterCredentials(
        cardAccessNumber: UITestEnvironment.cardAccessNumber,
        pin1: UITestEnvironment.pin1,
        in: app)
    }

    // MARK: Overridden Functions

    override internal func setUpWithError() throws {
      try super.setUpWithError()
      try XCTSkipUnless(
        UITestEnvironment.realCardTestsEnabled,
        "Set TEST_RUNNER_\(UITestEnvironment.realCardTestsVariable)=1 to run physical-card tests")
    }

    override internal func tearDownWithError() throws {
      MainActor.assumeIsolated {
        XCUIApplication().terminate()
      }
      try super.tearDownWithError()
    }

    // MARK: Functions

    /// Starts Safari setup from the card form and asserts registration.
    internal func testRegistersCardForSafari() {
      let app = UITestApp.launch()
      attachScreenshot(app.screenshot(), named: "01-setup-opened")
      Self.storeCredentialsIfGiven(in: app)
      app.swipeUp()

      let start = app.buttons[UITestIdentifiers.primeStartButton]
      guard start.waitForExistence(timeout: Self.appearTimeout), start.isEnabled else {
        attachScreenshot(app.screenshot(), named: "02-registration-unavailable")
        XCTFail(
          "Safari setup would not start from the current credential state")
        return
      }
      attachScreenshot(app.screenshot(), named: "02-registration-ready")
      start.tap()

      let identity = app.staticTexts[UITestIdentifiers.identityStatus]
      let registered = identity.waitForExistence(timeout: Self.primeTimeout)
      attachScreenshot(app.screenshot(), named: "03-registration-finished")
      XCTAssertTrue(
        registered,
        "the card was not registered for Safari")
    }
  }

#endif
