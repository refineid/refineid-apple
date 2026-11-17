// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import XCTest

  /// What every Mac journey needs: the status window, opened the way a
  /// holder opens it.
  ///
  /// The window is found by opening the app menu, not by naming a
  /// window that may not exist yet: a query for a missing window waits
  /// out its timeout and blames the window, while the menu path either
  /// opens it or fails at the click that should have.
  extension XCTestCase {
    /// Opens the status window through the app menu and answers it.
    @MainActor
    internal func openStatusWindow(_ app: XCUIApplication) -> XCUIElement {
      let windowMenu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "RefineID")
        .firstMatch
      XCTAssertTrue(windowMenu.waitForExistence(timeout: UITestApp.appearTimeout))
      windowMenu.click()
      app.menuItems["RefineID"].click()
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: UITestApp.appearTimeout))
      return window
    }
  }

#endif
