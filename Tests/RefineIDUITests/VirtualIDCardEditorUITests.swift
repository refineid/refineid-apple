// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// The virtual card editor, reached through the same GUI as a real card.
  @MainActor
  internal final class VirtualIDCardEditorUITests: XCTestCase {
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

    /// The audit arrived after the oldest system this app runs on, so
    /// this check is offered only where it exists.
    internal func testVirtualCardEditorPassesAccessibilityAudit() throws {
      let app = UITestApp.launchVirtualCard()
      let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
      XCTAssertTrue(overlay.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertEqual(overlay.label, "Virtual ID Card")
      XCTAssertFalse((overlay.value as? String ?? "").isEmpty)

      applyScenario("registered-nfc", in: app)
      openEditor(in: app)
      try app.performAccessibilityAudit { issue in
        XCTFail(
          """
          \(issue.compactDescription)
          \(issue.detailedDescription)
          Element: \(String(describing: issue.element))
          """)
        return true
      }
    }

    internal func testVirtualCardEditorIsLocalizedAndAccessibleInFinnish() {
      assertVirtualCardEditorLocalization(language: "fi")
    }

    internal func testVirtualCardEditorIsLocalizedAndAccessibleInSwedish() {
      assertVirtualCardEditorLocalization(language: "sv")
    }
  }
#endif
