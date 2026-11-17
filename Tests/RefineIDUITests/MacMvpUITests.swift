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

    /// The languages the app ships, in the order the tests ask for them.
    private static let languages = pinCodesLabels.keys.sorted()

    /// The prefixes a Settings item carries in the app's shipped
    /// languages, ASCII only: matching ignores case and diacritics.
    private static let settingsItemTitles = ["Settings", "Asetukset", "Installningar"]

    /// Matches a Settings item whatever shipped language the app speaks.
    private static let settingsItemPredicate = NSPredicate(
      format: "title BEGINSWITH[cd] %@ OR title BEGINSWITH[cd] %@ OR title BEGINSWITH[cd] %@",
      argumentArray: settingsItemTitles
    )

    /// The menu bar lists the Apple menu first, then the application's.
    private static let applicationMenuItemOrdinal = 1

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
      XCTAssertFalse(app.descendants(matching: .any)["documentDropArea"].firstMatch.exists)
      XCTAssertFalse(app.descendants(matching: .button)["verifyQueuedDocuments"].firstMatch.exists)
      let attachment = XCTAttachment(screenshot: window.screenshot())
      attachment.name = "window-no-card"
      attachment.lifetime = .keepAlways
      add(attachment)
    }

    /// No pane is compiled in, so the application menu carries no
    /// Settings item and the command that would open one opens no
    /// window, in every language the app ships.
    internal func testNoSettingsItemWithoutASettingsPane() {
      for language in Self.languages {
        let app = UITestApp.launch(
          language: language,
          arguments: ["--virtual-card", "absent", "--hide-diagnostics"])
        defer { app.terminate() }
        let applicationMenu = app.menuBars.menuBarItems
          .element(boundBy: Self.applicationMenuItemOrdinal)
        XCTAssertTrue(
          applicationMenu.waitForExistence(timeout: UITestApp.appearTimeout),
          "no application menu in \(language)")
        applicationMenu.click()
        XCTAssertFalse(
          app.menuItems.matching(Self.settingsItemPredicate).firstMatch.exists,
          "a Settings item appears in \(language)")
        let windows = app.windows.count
        app.typeKey(",", modifierFlags: [.command])
        XCTAssertEqual(
          app.windows.count, windows,
          "the Settings command opened a window in \(language)")
      }
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
      // The MVP carries no remote card or document verification: no
      // pairing field, no switch, and no Verify button.
      XCTAssertFalse(app.textFields[UITestIdentifiers.pairingCodeField].exists)
      XCTAssertFalse(
        app.descendants(matching: .button)[UITestIdentifiers.remoteUseSwitch].firstMatch.exists)
      XCTAssertFalse(app.descendants(matching: .button)["verifyQueuedDocuments"].firstMatch.exists)
      XCTAssertTrue(
        app.descendants(matching: .any)["documentDropArea"].firstMatch.waitForExistence(
          timeout: UITestApp.appearTimeout))
      if language == "en" {
        XCTAssertTrue(window.staticTexts["Drop documents here to sign them."].exists)
      }
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
