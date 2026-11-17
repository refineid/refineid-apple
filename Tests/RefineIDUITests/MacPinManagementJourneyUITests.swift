// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import XCTest

  /// PIN management on the Mac with the virtual card, end to end.
  ///
  /// The key beside the holder's name opens the PIN codes window, where
  /// changing PIN 1 asks for confirmation first and reports the change,
  /// cancelling sends nothing to the card, and a wrong current PIN is
  /// refused with the attempts left. No live card: the virtual card
  /// holds PIN 1 1234 with five attempts.
  @MainActor
  internal final class MacPinManagementJourneyUITests: XCTestCase {
    /// The virtual card's PIN 1, and the value the journeys change it to.
    private static let pin1 = "1234"
    private static let changedPin1 = "4321"
    private static let wrongPin1 = "1111"

    /// Opens the PIN codes window on the virtual card's holder.
    private func openPinCodes(_ app: XCUIApplication) {
      _ = openStatusWindow(app)
      let key = app.descendants(matching: .button)[UITestIdentifiers.pinCodesButton]
        .firstMatch
      XCTAssertTrue(
        key.waitForExistence(timeout: UITestApp.appearTimeout),
        "no key beside the holder's name")
      key.click()
      XCTAssertTrue(
        pinCodes(app).waitForExistence(timeout: UITestApp.appearTimeout),
        "the PIN codes window did not open")
    }

    /// The PIN codes window, resolved fresh: a held reference goes
    /// stale across the window's content transitions.
    private func pinCodes(_ app: XCUIApplication) -> XCUIElement {
      app.windows[UITestIdentifiers.pinCodesWindow].firstMatch
    }

    /// Types `text` into `field`, replacing whatever it holds.
    private func fill(_ field: XCUIElement, with text: String) {
      field.click()
      field.typeKey("a", modifierFlags: .command)
      field.typeText(text)
    }

    /// Changes PIN 1 from `current` to `new`, answering the confirmation.
    private func changePin1(
      from current: String, to new: String, confirming: Bool, in app: XCUIApplication
    ) {
      let codes = pinCodes(app)
      codes.radioButtons["Change PIN 1"].firstMatch.click()
      fill(
        codes.secureTextFields[UITestIdentifiers.managementChangePin1Current].firstMatch,
        with: current)
      fill(
        codes.secureTextFields[UITestIdentifiers.managementChangePin1New].firstMatch, with: new)
      fill(
        codes.secureTextFields[UITestIdentifiers.managementChangePin1Repeat].firstMatch, with: new)
      codes.buttons[UITestIdentifiers.managementChangePin1].firstMatch.click()
      let sheet = codes.sheets.firstMatch
      XCTAssertTrue(
        sheet.waitForExistence(timeout: UITestApp.appearTimeout),
        "no confirmation for the PIN 1 change")
      if confirming {
        sheet.buttons[UITestIdentifiers.managementConfirm].firstMatch.click()
      } else {
        sheet.buttons[UITestIdentifiers.managementCancel].firstMatch.click()
      }
    }

    /// Whether the window speaks `text` somewhere in its tree.
    private func speaks(_ text: String, in app: XCUIApplication) -> Bool {
      let window = pinCodes(app)
      return window.descendants(matching: .any)
        .containing(NSPredicate(format: "label CONTAINS %@", text))
        .firstMatch
        .waitForExistence(timeout: UITestApp.appearTimeout)
    }

    /// Changing PIN 1 asks first and reports the change.
    internal func testChangePin1AsksThenReports() {
      let app = UITestApp.launch(
        arguments: ["--virtual-card", "activated-reader", "--hide-diagnostics"])
      defer { app.terminate() }
      openPinCodes(app)
      changePin1(from: Self.pin1, to: Self.changedPin1, confirming: true, in: app)
      XCTAssertTrue(
        speaks("Basic PIN 1 changed.", in: app),
        "no report for the changed PIN 1")
    }

    /// Cancelling the confirmation sends nothing: the original PIN 1
    /// still verifies on the very next change.
    internal func testCancellingChangeSendsNothing() {
      let app = UITestApp.launch(
        arguments: ["--virtual-card", "activated-reader", "--hide-diagnostics"])
      defer { app.terminate() }
      openPinCodes(app)
      changePin1(from: Self.pin1, to: Self.changedPin1, confirming: false, in: app)
      XCTAssertFalse(
        speaks("Basic PIN 1 changed.", in: app),
        "a cancelled change reported success")
      changePin1(from: Self.pin1, to: Self.changedPin1, confirming: true, in: app)
      XCTAssertTrue(
        speaks("Basic PIN 1 changed.", in: app),
        "the original PIN 1 no longer verifies after the cancel")
    }

    /// A wrong current PIN 1 is refused with the attempts left.
    internal func testWrongCurrentPin1RefusesWithAttemptsLeft() {
      let app = UITestApp.launch(
        arguments: ["--virtual-card", "activated-reader", "--hide-diagnostics"])
      defer { app.terminate() }
      openPinCodes(app)
      changePin1(from: Self.wrongPin1, to: Self.changedPin1, confirming: true, in: app)
      XCTAssertTrue(
        speaks("4 attempts remaining", in: app),
        "the refusal names no attempts left")
    }
  }

#endif
