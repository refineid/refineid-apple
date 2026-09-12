// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// The reveal eye swaps a secret field for a standard text field
  /// showing the same digits, and hiding restores secret entry.
  @MainActor
  internal final class CredentialRevealUITests: XCTestCase {
    private static let appearTimeout: TimeInterval = 10

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

    internal func testRevealSwapsToStandardFieldAndBack() {
      let app = UITestApp.launchVirtualCard(scenario: "activated-reader")
      let key = app.buttons[UITestIdentifiers.pinManagementButton]
      XCTAssertTrue(key.waitForExistence(timeout: Self.appearTimeout))
      key.tap()

      let secret = app.secureTextFields["managementChangePIN1Current"]
      XCTAssertTrue(secret.waitForExistence(timeout: Self.appearTimeout))
      secret.tap()
      secret.typeText("1234")

      app.buttons["managementChangePIN1CurrentReveal"].tap()
      let revealed = app.textFields["managementChangePIN1Current"]
      XCTAssertTrue(
        revealed.waitForExistence(timeout: Self.appearTimeout),
        "revealing did not present a standard text field")
      XCTAssertEqual(
        revealed.value as? String,
        "1234",
        "the revealed field does not show the entered digits")
      XCTAssertFalse(
        secret.exists,
        "the secret field remained alongside the revealed value")

      app.buttons["managementChangePIN1CurrentReveal"].tap()
      XCTAssertTrue(
        secret.waitForExistence(timeout: Self.appearTimeout),
        "hiding did not restore the secret field")
      XCTAssertFalse(
        revealed.exists,
        "the revealed field remained after hiding")
    }
  }

#endif
