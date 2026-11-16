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

    /// The prefix a Settings item carries when a pane needs one.
    private static let settingsItemTitlePrefix = "Settings"

    internal func testEnglishLocalCard() {
      checkLocalCard(language: "en")
    }

    internal func testFinnishLocalCard() {
      checkLocalCard(language: "fi")
    }

    internal func testSwedishLocalCard() {
      checkLocalCard(language: "sv")
    }

    internal func testNoCardShowsReaderInstructionAndNoRemoteUI() {
      let app = UITestApp.launch(arguments: [
        "--virtual-card", "absent", "--hide-diagnostics", UITestApp.remoteUseOnArgument,
      ])
      defer { app.terminate() }
      let windowMenu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "RefineID")
        .firstMatch
      XCTAssertTrue(windowMenu.waitForExistence(timeout: UITestApp.appearTimeout))
      windowMenu.click()
      app.menuItems["RefineID"].click()
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: UITestApp.appearTimeout))
      // With no card and no remote card, the row asks for a reader:
      // no pairing field, no switch, and no key.
      let identity = app.descendants(matching: .any)["loginIdentityStatus"].firstMatch
      XCTAssertTrue(identity.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertTrue(
        window.staticTexts["Connect a card reader."].waitForExistence(
          timeout: UITestApp.appearTimeout))
      XCTAssertFalse(app.textFields[UITestIdentifiers.pairingCodeField].exists)
      XCTAssertFalse(
        app.descendants(matching: .button)[UITestIdentifiers.remoteUseSwitch].firstMatch.exists)
      XCTAssertFalse(
        app.descendants(matching: .button)[UITestIdentifiers.pinManagementButton].firstMatch
          .exists)
    }

    /// No pane is compiled in, so the app menu carries no Settings item
    /// and the app has no window for one.
    internal func testNoSettingsItemWithoutASettingsPane() {
      let app = UITestApp.launch(
        arguments: ["--virtual-card", "absent", "--hide-diagnostics"])
      defer { app.terminate() }
      let windowMenu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "RefineID")
        .firstMatch
      XCTAssertTrue(windowMenu.waitForExistence(timeout: UITestApp.appearTimeout))
      windowMenu.click()
      let settingsItems = app.menuItems.matching(
        NSPredicate(
          format: "title BEGINSWITH[c] %@ OR title BEGINSWITH[c] %@",
          Self.settingsItemTitlePrefix, "Asetukset"))
      XCTAssertEqual(settingsItems.count, 0)
    }

    private func openMainWindow(_ app: XCUIApplication) {
      let windowMenu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "RefineID")
        .firstMatch
      XCTAssertTrue(windowMenu.waitForExistence(timeout: UITestApp.appearTimeout))
      windowMenu.click()
      app.menuItems["RefineID"].click()
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: UITestApp.appearTimeout))
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
