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

    /// The shipped address the field shows with nothing stored.
    private static let defaultAddress = "http://timestamp.sectigo.com/qualified"

    /// How long the automatic probe may take to fail.
    private static let verdictTimeout: TimeInterval = 20

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

    internal func testUnprovenDraftRevertsToStoredAddress() {
      let app = UITestApp.launch(
        language: "fi",
        arguments: ["--virtual-card", "absent", "--hide-diagnostics"])
      defer { app.terminate() }
      openMainWindow(app)
      app.typeKey(",", modifierFlags: [.command])
      let field = app.textFields["timestampAuthorityField"].firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      let settingsWindow = app.windows.containing(
        .textField, identifier: "timestampAuthorityField"
      ).firstMatch
      let restore = app.buttons["timestampRestoreButton"].firstMatch
      let badge = app.descendants(matching: .any)["timestampStatusBadge"].firstMatch
      // A stored address from an earlier run restores first.
      if field.value as? String != Self.defaultAddress {
        restore.click()
        expectation(
          for: NSPredicate(format: "value == %@", Self.defaultAddress),
          evaluatedWith: field)
        waitForExpectations(timeout: UITestApp.appearTimeout)
      }
      XCTAssertFalse(restore.exists)
      // The shipped authority is never probed: past the debounce the
      // badge still shows untested.
      sleep(3)
      XCTAssertEqual(badge.label, "Ei testattu")
      // A fresh refused port per run: no recorded verdict can answer
      // for the probe, so the badge proves the automatic test ran.
      let port = 20_000 + Int(Date().timeIntervalSince1970) % 20_000
      field.click()
      app.typeKey("a", modifierFlags: [.command])
      field.typeText("127.0.0.1:\(port)/tsa")
      XCTAssertTrue(restore.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertTrue(badge.waitForExistence(timeout: UITestApp.appearTimeout))
      expectation(
        for: NSPredicate(format: "label CONTAINS %@", "Epäonnistui"),
        evaluatedWith: badge)
      waitForExpectations(timeout: Self.verdictTimeout)
      let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      attachment.name = "timestamp-settings-unproven"
      attachment.lifetime = .keepAlways
      add(attachment)
      // The unproven draft was never stored: reopening shows the default.
      settingsWindow.buttons[XCUIIdentifierCloseWindow].firstMatch.click()
      expectation(
        for: NSPredicate(format: "exists == false"),
        evaluatedWith: field)
      waitForExpectations(timeout: UITestApp.appearTimeout)
      app.typeKey(",", modifierFlags: [.command])
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertEqual(field.value as? String, Self.defaultAddress)
      XCTAssertFalse(restore.exists)
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
