// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import XCTest

  /// Taking a factory-fresh card into use on the Mac, end to end.
  ///
  /// A factory-fresh virtual card replaces the window with the
  /// activation form, the holder enters the activation PIN and chooses
  /// PIN 1 and PIN 2, confirms, and the window names the holder. No
  /// live card: the activation PIN is 1234567.
  @MainActor
  internal final class MacActivationJourneyUITests: XCTestCase {
    /// The virtual card's activation PIN.
    private static let activationEntry = "1234567"

    /// The PIN 1 and PIN 2 the journeys choose.
    private static let pin1 = "1234"
    private static let pin2 = "123456"

    /// Whether the window shows `text` somewhere in its tree.
    private func speaks(_ text: String, in window: XCUIElement) -> Bool {
      window.descendants(matching: .any)
        .containing(NSPredicate(format: "label CONTAINS %@", text))
        .firstMatch
        .waitForExistence(timeout: UITestApp.appearTimeout)
    }

    /// Types `text` into `field`, replacing whatever it holds.
    private func fill(_ field: XCUIElement, with text: String) {
      field.click()
      field.typeKey("a", modifierFlags: .command)
      field.typeText(text)
    }

    /// Activating the factory-fresh card names its holder.
    internal func testActivateFactoryFreshCard() {
      let app = UITestApp.launch(
        arguments: ["--virtual-card", "factory-fresh-reader", "--hide-diagnostics"])
      defer { app.terminate() }
      let window = openStatusWindow(app)
      let entry = window.secureTextFields[UITestIdentifiers.managementActivationEntry].firstMatch
      XCTAssertTrue(
        entry.waitForExistence(timeout: UITestApp.appearTimeout),
        "no activation form for the factory-fresh card")
      fill(entry, with: Self.activationEntry)
      fill(
        window.secureTextFields[UITestIdentifiers.managementActivationPin1].firstMatch,
        with: Self.pin1)
      fill(
        window.secureTextFields[UITestIdentifiers.managementActivationPin1Repeat].firstMatch,
        with: Self.pin1)
      fill(
        window.secureTextFields[UITestIdentifiers.managementActivationPin2].firstMatch,
        with: Self.pin2)
      fill(
        window.secureTextFields[UITestIdentifiers.managementActivationPin2Repeat].firstMatch,
        with: Self.pin2)
      window.buttons[UITestIdentifiers.managementActivate].firstMatch.click()
      let sheet = window.sheets.firstMatch
      XCTAssertTrue(
        sheet.waitForExistence(timeout: UITestApp.appearTimeout),
        "no confirmation for the activation")
      sheet.buttons[UITestIdentifiers.managementConfirm].firstMatch.click()
      XCTAssertTrue(
        speaks("DOE JANE", in: window),
        "the activated card names no holder")
    }
  }

#endif
