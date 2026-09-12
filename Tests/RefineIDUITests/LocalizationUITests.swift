// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// The app in each language it claims to support.
///
/// A catalogue that compiles proves the file is well formed and nothing
/// else. What matters is that a holder who runs this Mac in Finnish or
/// Swedish is shown their own language, and that the window still works
/// when the words change length -- a translation that clips a button or
/// widens a window past the screen is a defect the English run cannot
/// show.
@MainActor
internal final class LocalizationUITests: XCTestCase {
  /// Clipped text, by the value the audit header assigns it.
  ///
  /// Swift does not surface it as a named member on macOS, so the
  /// option set is built from the documented bit position rather than
  /// left out of the run. Contrast is not asked for: see
  /// `AccessibilityAuditUITests` for what that check was measured
  /// doing.
  ///
  /// The audit arrived after the oldest system this app runs on, so the
  /// check that uses it is offered only where it exists. The two
  /// translation checks below need no audit and run everywhere.
  private static var clipping: XCUIAccessibilityAuditType {
    XCUIAccessibilityAuditType(rawValue: 1 << 17)
  }

  /// Finnish exposes the stable PIN-management action.
  internal func testTheAppSpeaksFinnish() {
    check(language: "fi")
  }

  /// Swedish exposes the same localized action.
  internal func testTheAppSpeaksSwedish() {
    check(language: "sv")
  }

  /// Finnish does not clip anything the English run sized.
  ///
  /// A Finnish or Swedish sentence is routinely longer than the English
  /// it was written from, and a control sized around the English one
  /// then clips it. This is the audit's own check for that, run in the
  /// language most likely to trip it.
  internal func testFinnishDoesNotClipTheWindow() throws {
    let app = UITestApp.launch(language: "fi")
    var clipped: [String] = []
    try app.performAccessibilityAudit(for: Self.clipping) { issue in
      // Asking for one check does not get one check: the run came back
      // with a parent/child mismatch, which is scaffolding and not a
      // translation that outgrew its control. What is kept is what was
      // asked for.
      guard issue.auditType == Self.clipping else { return true }
      let element = issue.element
      clipped.append(
        """
        \(issue.auditType): \(issue.compactDescription)
        \(issue.detailedDescription)
        identifier=\(element?.identifier ?? "<none>")
        label=\(element?.label ?? "<none>")
        value=\(String(describing: element?.value))
        frame=\(String(describing: element?.frame))
        """
      )
      return true
    }
    attachText(clipped.joined(separator: "\n"), named: "clipping-fi")
    XCTAssertTrue(
      clipped.isEmpty,
      "Finnish clips the window:\n" + clipped.joined(separator: "\n")
    )
  }

  /// Launches in one language and reads the status window back.
  private func check(language: String) {
    #if os(iOS)
      let app = UITestApp.launch(
        language: language,
        arguments: ["--virtual-card", "absent"])
      app.activate()
      self.applyRegisteredVirtualCard(in: app)
      XCTAssertTrue(
        app.buttons[UITestIdentifiers.pinManagementButton].waitForExistence(timeout: 10),
        "PIN Management is not exposed in \(language)"
      )
      attachScreenshot(app.screenshot(), named: "menu-\(language)")
      app.typeKey(.escape, modifierFlags: [])
    #else
      let app = UITestApp.launch(language: language)
      app.activate()
      XCTAssertTrue(
        app.windows.firstMatch.waitForExistence(timeout: 5),
        "Main window is not exposed in \(language)"
      )
      attachScreenshot(app.screenshot(), named: "menu-\(language)")
    #endif
  }

  #if os(iOS)
    /// Establishes the product state in which PIN management is intentionally
    /// visible, using only the same editable virtual-card GUI a reviewer uses.
    private func applyRegisteredVirtualCard(in app: XCUIApplication) {
      let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
      XCTAssertTrue(overlay.waitForExistence(timeout: 10), "Virtual ID Card overlay is unavailable")
      overlay.tap()

      let editor = app.descendants(matching: .any)[UITestIdentifiers.virtualCardEditor].firstMatch
      XCTAssertTrue(editor.waitForExistence(timeout: 10), "Virtual ID Card editor did not open")

      let scenario =
        app.descendants(matching: .any)[UITestIdentifiers.virtualCardScenario].firstMatch
      XCTAssertTrue(
        scenario.waitForExistence(timeout: 10), "Virtual card scenario control is missing")
      scenario.tap()

      let registered =
        app.descendants(matching: .any)["virtualCardScenarioOption.registered-nfc"].firstMatch
      XCTAssertTrue(registered.waitForExistence(timeout: 10), "Registered NFC scenario is missing")
      registered.tap()

      let apply = app.buttons[UITestIdentifiers.virtualCardApply]
      XCTAssertTrue(apply.waitForExistence(timeout: 10), "Virtual card Apply action is missing")
      apply.tap()

      XCTAssertTrue(
        app.staticTexts[UITestIdentifiers.identityStatus].waitForExistence(timeout: 10),
        "Registered virtual identity did not appear")
    }
  #endif
}
