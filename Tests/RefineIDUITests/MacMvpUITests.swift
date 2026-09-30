// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import XCTest

  @MainActor
  internal final class MacMvpUITests: XCTestCase {
    internal func testEnglishLocalCard() {
      checkLocalCard(language: "en")
    }

    internal func testFinnishLocalCard() {
      checkLocalCard(language: "fi")
    }

    internal func testSwedishLocalCard() {
      checkLocalCard(language: "sv")
    }

    private func checkLocalCard(language: String) {
      let app = UITestApp.launch(
        language: language,
        arguments: ["--virtual-card", "activated-reader", "--hide-diagnostics"])
      defer { app.terminate() }
      let windowMenu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "RefineID")
        .firstMatch
      XCTAssertTrue(windowMenu.waitForExistence(timeout: UITestApp.appearTimeout))
      windowMenu.click()
      app.menuItems["RefineID"].click()
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: UITestApp.appearTimeout))
      let identity = app.descendants(matching: .any)["loginIdentityStatus"].firstMatch
      XCTAssertTrue(identity.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(app.textFields["pairingCode"].exists)
      let attachment = XCTAttachment(screenshot: window.screenshot())
      attachment.name = "window-card-\(language)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }
#endif
