// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import XCTest

  @MainActor
  internal final class MacMvpUITests: XCTestCase {
    /// What VoiceOver reads for the key beside the holder's name.
    private static let pinCodesLabels = [
      "en": "PIN Codes",
      "fi": "PIN-koodit",
      "sv": "PIN-koder",
    ]

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
      XCTAssertEqual(window.title, "RefineID")
      let identity = app.descendants(matching: .any)["loginIdentityStatus"].firstMatch
      XCTAssertTrue(identity.waitForExistence(timeout: UITestApp.appearTimeout))
      // The MVP carries no remote card: no pairing field, no switch.
      XCTAssertFalse(app.textFields[UITestIdentifiers.pairingCodeField].exists)
      XCTAssertFalse(
        app.descendants(matching: .button)[UITestIdentifiers.remoteUseSwitch].firstMatch.exists)
      // The key beside the holder's name speaks the window language.
      let key = app.descendants(matching: .button)[UITestIdentifiers.pinManagementButton]
        .firstMatch
      XCTAssertTrue(
        key.waitForExistence(timeout: UITestApp.appearTimeout),
        "no key beside the holder's name")
      XCTAssertEqual(key.label, Self.pinCodesLabels[language])
      let attachment = XCTAttachment(screenshot: window.screenshot())
      attachment.name = "window-card-\(language)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }
#endif
