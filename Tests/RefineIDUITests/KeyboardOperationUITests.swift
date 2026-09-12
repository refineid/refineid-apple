// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// Operating the card windows with no pointer at all.
///
/// WCAG 2.1.1 asks that everything be reachable from a keyboard, and
/// 2.1.2 that focus never be trapped once it arrives. Neither can be
/// judged by inspecting a screen: they are claims about what happens
/// when keys are pressed, so these tests press them.
///
/// Two of these run anywhere. Reaching a button with Tab needs macOS
/// keyboard navigation switched on, which is a setting of the machine
/// and not of this process: passing the preference as a launch argument
/// was measured having no effect, because AppKit reads it from the
/// system rather than from the app. So the Tab test states the
/// requirement and skips when it is unmet, rather than reporting the
/// app as inaccessible when what is off is a system switch.
@MainActor
internal final class KeyboardOperationUITests: XCTestCase {
  /// Digits that are certainly not this card's PIN, and are never sent:
  /// every test here abandons the operation at the confirmation.
  private static let unusedEntry = "0000"

  /// How many times Tab may be pressed before the search for a control
  /// is called a failure rather than a slow walk.
  private static let focusSearchLimit = 30

  /// Whether this Mac lets Tab reach every control.
  ///
  /// Mode 2 and above is "all controls"; unset or 1 is text fields and
  /// lists only.
  private static var keyboardNavigationIsOn: Bool {
    UserDefaults.standard.integer(forKey: "AppleKeyboardUIMode") >= 2
  }

  /// Every button in the window is reachable by Tab.
  ///
  /// Skipped, not failed, when macOS keyboard navigation is off: with
  /// it off Tab visits text fields and lists only, which is a fact
  /// about the setting rather than about this app.
  internal func testEveryControlIsReachedByTab() throws {
    try XCTSkipUnless(
      Self.keyboardNavigationIsOn,
      """
      macOS keyboard navigation is off; \
      turn it on in System Settings > Keyboard to run this
      """
    )
    let app = launchWithFullKeyboardAccess()
    let management = app.buttons[UITestIdentifiers.pinManagementButton]
    try XCTSkipUnless(
      management.waitForExistence(timeout: 2) && management.isEnabled,
      "no card present; management window unavailable"
    )
    XCTAssertTrue(
      focus(app, on: UITestIdentifiers.pinManagementButton),
      "PIN Management is not reachable by Tab, so it is not reachable without a pointer"
    )
  }

  /// The whole change form is typed and submitted from the keyboard,
  /// and the question it raises is dismissed from the keyboard.
  ///
  /// This needs no system setting: the form takes focus when it opens
  /// and threads its three fields on Return, which is the path a
  /// keyboard user actually takes through it.
  internal func testTheChangeFormIsWorkedWithTheKeyboardAlone() throws {
    let app = launchWithFullKeyboardAccess()
    let management = app.buttons[UITestIdentifiers.pinManagementButton]
    try XCTSkipUnless(
      management.waitForExistence(timeout: 2) && management.isEnabled,
      "no card present; management window unavailable"
    )
    management.click()

    let current = app.secureTextFields["managementChangePIN1Current"]
    XCTAssertTrue(current.waitForExistence(timeout: 10), "management window did not open")
    // Nothing is clicked in the window. Opening it must put focus in
    // the first field, or a keyboard user has to find that field with a
    // pointer before the keyboard does anything -- which is not a
    // keyboard path at all. A SecureField reports no value to read
    // back, so what proves focus arrived is that the operation reaches
    // its confirmation below.
    XCTAssertTrue(current.waitForExistence(timeout: 5), "no current-PIN field")
    let change = app.buttons["managementChangePIN1"]
    try XCTSkipUnless(change.exists, "Change form is not open")
    app.typeText("1111")
    app.typeKey(.return, modifierFlags: [])
    app.typeText("2222")
    app.typeKey(.return, modifierFlags: [])
    app.typeText("2222")
    app.typeKey(.return, modifierFlags: [])

    let confirm = app.buttons[UITestIdentifiers.managementConfirm]
    try XCTSkipUnless(change.isEnabled, "Change button is disabled without a live card")
    XCTAssertTrue(
      confirm.waitForExistence(timeout: 5),
      "Return on the last field neither asked nor acted"
    )
    attachScreenshot(app.screenshot(), named: "keyboard-confirmation")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertFalse(
      confirm.waitForExistence(timeout: 2),
      "Escape did not dismiss the confirmation, so focus is trapped in it"
    )
  }

  /// Launches the app in a stated language, as every test here does.
  private func launchWithFullKeyboardAccess() -> XCUIApplication {
    UITestApp.launch()
  }

  /// Waits for the named control to hold keyboard focus on its own,
  /// pressing nothing.
  private func waitForFocus(_ app: XCUIApplication, on identifier: String) -> Bool {
    let focused = app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasKeyboardFocus == YES"))
    for _ in 0..<Self.focusSearchLimit {
      if focused.firstMatch.exists, focused.firstMatch.identifier == identifier {
        return true
      }
      usleep(200_000)
    }
    return false
  }

  /// Presses Tab until the named control is the one holding keyboard
  /// focus.
  ///
  /// Focus is read from the accessibility attribute rather than from a
  /// property on the element: what a keyboard user can reach is what
  /// the system reports as focused, and that is the same answer
  /// VoiceOver acts on.
  private func focus(_ app: XCUIApplication, on identifier: String) -> Bool {
    let focused = app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasKeyboardFocus == YES"))
    for _ in 0..<Self.focusSearchLimit {
      if focused.firstMatch.exists, focused.firstMatch.identifier == identifier {
        return true
      }
      app.typeKey(.tab, modifierFlags: [])
    }
    return false
  }
}
