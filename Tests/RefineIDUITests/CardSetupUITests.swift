// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// Card setup, driven the way a holder drives it: type the access number,
/// then observe that the hold starts by itself.
///
/// The value comes from the test runner's environment and is never
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

  /// Enters the access number and asserts that the hold starts by itself.
  ///
  /// No card is needed: the prompt dismissing proves the hold started,
  /// and the NFC sheet waits for a card that never comes until the run
  /// ends the app.
  internal func testCompleteEntryStartsTheHoldThroughGUI() throws {
    let cardAccessNumber = try XCTUnwrap(
      UITestEnvironment.cardAccessNumber,
      Self.missing(UITestEnvironment.cardAccessNumberVariable))

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
      in: app)
    XCTAssertTrue(
      entered,
      "the card access number field could not be filled")

    let field = app.descendants(matching: .any)[
      UITestIdentifiers.cardAccessNumberField
    ]
    let dismissed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: field)
    XCTAssertEqual(
      XCTWaiter.wait(for: [dismissed], timeout: 10),
      .completed,
      "a complete entry did not start the hold by itself")
  }
}
