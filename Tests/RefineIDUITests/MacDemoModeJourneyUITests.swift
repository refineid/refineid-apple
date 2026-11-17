// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import XCTest

  /// Demonstration mode on the Mac, end to end.
  ///
  /// With no card anywhere, Demo Mode puts a factory-fresh virtual card
  /// in a fictional reader and marks the window, the card editor opens
  /// from its shortcut and switches to an activated card with a pending
  /// signing request, and turning the mode off takes the window back to
  /// no card.
  @MainActor
  internal final class MacDemoModeJourneyUITests: XCTestCase {
    private static let absentWaitSeconds: TimeInterval = 2

    /// Demo mode on, a document from the editor, and off again.
    internal func testDemoModeShowsCardAndEditorSuppliesDocument() {
      let app = UITestApp.launch(arguments: ["--hide-diagnostics"])
      defer { app.terminate() }
      app.activate()
      let window = openStatusWindow(app)
      XCTAssertFalse(
        app.descendants(matching: .any)[UITestIdentifiers.demoModeNotice].firstMatch
          .waitForExistence(timeout: Self.absentWaitSeconds),
        "a cold window claims demonstration mode")
      app.typeKey("d", modifierFlags: [.command, .option])
      XCTAssertTrue(
        app.descendants(matching: .any)[UITestIdentifiers.demoModeNotice].firstMatch
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "Demo Mode marked no window")
      app.typeKey("e", modifierFlags: [.command, .option])
      let editor = app.descendants(matching: .any)[UITestIdentifiers.virtualCardEditor].firstMatch
      XCTAssertTrue(
        editor.waitForExistence(timeout: UITestApp.appearTimeout),
        "the card editor did not open")
      let scenario = app.descendants(matching: .any)[UITestIdentifiers.virtualCardScenario]
        .firstMatch
      XCTAssertTrue(
        scenario.waitForExistence(timeout: UITestApp.appearTimeout),
        "no scenario picker in the card editor")
      scenario.click()
      let activatedOption = app.descendants(matching: .any)[
        "virtualCardScenarioOption.activated-reader"
      ].firstMatch
      if activatedOption.waitForExistence(timeout: Self.absentWaitSeconds) {
        activatedOption.click()
      }
      app.descendants(matching: .button)[UITestIdentifiers.virtualCardSigningPending].firstMatch
        .click()
      app.descendants(matching: .button)[UITestIdentifiers.virtualCardApply].firstMatch.click()
      XCTAssertTrue(
        window.staticTexts["Review document.pdf"].firstMatch.waitForExistence(
          timeout: UITestApp.appearTimeout),
        "the editor supplied no document")
      app.typeKey("d", modifierFlags: [.command, .option])
      XCTAssertFalse(
        app.descendants(matching: .any)[UITestIdentifiers.demoModeNotice].firstMatch
          .waitForExistence(timeout: Self.absentWaitSeconds),
        "Demo Mode stayed on")
    }
  }

#endif
