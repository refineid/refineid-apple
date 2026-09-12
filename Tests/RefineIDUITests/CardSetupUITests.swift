// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// Card setup, driven the way a holder drives it: type the access number
/// and PIN1, then observe that the one minting action becomes available.
///
/// Both values come from the test runner's environment and neither is
/// written down here. Physical-card tests require an explicit opt-in; after
/// that opt-in a missing credential fails and names the missing variable.
@MainActor
internal final class CardSetupUITests: XCTestCase {
  // MARK: Static Functions

  /// What to say when the run was not given a value it cannot invent.
  ///
  /// The message names the exact placement, because the wrong one fails
  /// silently: appended after the arguments the assignment is taken as a
  /// build setting and never reaches the runner.
  private static func missing(_ variable: String) -> String {
    "\(variable) was not set on the test runner. Set it in xcodebuild's own "
      + "environment, BEFORE the command: "
      + "TEST_RUNNER_\(variable)=... xcodebuild test ... - not appended "
      + "after the arguments, and not as a plain exported variable."
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

  /// Enters both credentials and asserts that identity creation is ready.
  internal func testAcceptsCredentialsForIdentityMinting() throws {
    let cardAccessNumber = try XCTUnwrap(
      UITestEnvironment.cardAccessNumber,
      Self.missing(UITestEnvironment.cardAccessNumberVariable))
    let pin1 = try XCTUnwrap(
      UITestEnvironment.pin1,
      Self.missing(UITestEnvironment.pin1Variable))

    let app = UITestApp.launch()
    attachScreenshot(app.screenshot(), named: "01-setup-opened")
    // Sizes, never values: this is what catches a shell that ate a
    // leading zero, and it is all a result bundle may know about them.
    attachText(
      """
      card access number digits: \(cardAccessNumber.count)
      """,
      named: "02-input-sizes")

    let entered = CardSetupScreen.enterCredentials(
      cardAccessNumber: cardAccessNumber,
      pin1: pin1,
      in: app)
    attachScreenshot(app.screenshot(), named: "03-credentials-entered")
    XCTAssertTrue(
      entered,
      "one of the two credential fields could not be filled")

    let mint = app.buttons[UITestIdentifiers.primeStartButton]
    XCTAssertTrue(
      mint.waitForExistence(timeout: 10) && mint.isEnabled,
      "valid CAN and PIN1 did not enable identity minting")
  }
}
