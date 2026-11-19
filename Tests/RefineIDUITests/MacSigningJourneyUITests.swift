// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import XCTest

  /// Signing a document on the Mac with the virtual card, end to end.
  ///
  /// A requested signature seeds the pile with the fictional document,
  /// the holder types PIN 2 and signs, the save panel is answered, and
  /// the window names what became of the signature. A wrong PIN 2 is
  /// refused in words with the attempts left, and retrying with the
  /// right one succeeds.
  /// No live card and no pre-placed file: the virtual card holds PIN 2 123456.
  @MainActor
  internal final class MacSigningJourneyUITests: XCTestCase {
    /// The virtual card's PIN 2, and a wrong one of valid shape.
    private static let pin2 = "123456"
    private static let wrongPin2 = "654321"
    private static let panelWaitSeconds: TimeInterval = 2

    /// The launch arguments every signing journey needs.
    private static var signingArguments: [String] {
      ["--virtual-card", "activated-reader", "--open-document-signing", "--hide-diagnostics"]
    }

    /// Signs the requested document and saves it through the panel.
    internal func testSignDocumentWithVirtualCard() {
      let app = UITestApp.launch(arguments: Self.signingArguments)
      defer { app.terminate() }
      let window = openStatusWindow(app)
      confirmSavePanel(
        afterSigningWith: Self.pin2, in: app, window: window)
      let row = app.descendants(matching: .any)[UITestIdentifiers.statusMessage].firstMatch
      XCTAssertTrue(
        row.waitForExistence(timeout: UITestApp.appearTimeout),
        "no outcome row after signing")
      XCTAssertTrue(
        window.staticTexts["Signed and saved."].waitForExistence(
          timeout: UITestApp.appearTimeout))
      XCTAssertFalse(
        window.buttons[UITestIdentifiers.statusAcknowledge].exists,
        "a saved signature should not require an acknowledgement button")
    }

    /// A wrong PIN 2 is refused with the attempts left, and the next explicit
    /// signing attempt with the right one succeeds.
    internal func testWrongPin2RefusesThenRightPin2Signs() {
      let app = UITestApp.launch(arguments: Self.signingArguments)
      defer { app.terminate() }
      let window = openStatusWindow(app)
      signWith(Self.wrongPin2, in: app, window: window)
      XCTAssertTrue(
        speaks("Signature PIN 2 is incorrect.", in: window),
        "no refusal for the wrong PIN 2")
      XCTAssertTrue(
        speaks("4 attempts remaining", in: window),
        "the refusal names no attempts left")
      XCTAssertFalse(
        window.sheets.firstMatch.waitForExistence(timeout: Self.panelWaitSeconds),
        "a refused signature asked where to save")
      XCTAssertFalse(window.buttons[UITestIdentifiers.statusAcknowledge].exists)
      confirmSavePanel(
        afterSigningWith: Self.pin2, in: app, window: window)
      XCTAssertTrue(
        window.staticTexts["Signed and saved."].waitForExistence(
          timeout: UITestApp.appearTimeout))
    }

    /// Whether the window shows `text` in one of its elements.
    ///
    /// Multi-line outcome texts combine their lines into one element,
    /// so the query spans every type, not just static text.
    private func speaks(_ text: String, in window: XCUIElement) -> Bool {
      window.descendants(matching: .any)
        .containing(NSPredicate(format: "label CONTAINS %@", text))
        .firstMatch
        .waitForExistence(timeout: UITestApp.appearTimeout)
    }

    /// Types `pin2` and presses the window's Sign button.
    private func signWith(
      _ pin2: String, in app: XCUIApplication, window: XCUIElement
    ) {
      let document = window.staticTexts["Review document.pdf"].firstMatch
      XCTAssertTrue(
        document.waitForExistence(timeout: UITestApp.appearTimeout),
        "the requested document never reached the pile")
      let field = app.descendants(matching: .secureTextField)[UITestIdentifiers.signPin2]
        .firstMatch
      XCTAssertTrue(
        field.waitForExistence(timeout: UITestApp.appearTimeout),
        "no PIN 2 field beside the waiting document")
      field.click()
      field.typeText(pin2)
      let sign = app.descendants(matching: .button)[UITestIdentifiers.signDocument].firstMatch
      XCTAssertTrue(
        sign.waitForExistence(timeout: UITestApp.appearTimeout),
        "no Sign button beside the waiting document")
      XCTAssertTrue(sign.isEnabled, "Sign stayed disabled with a complete PIN 2")
      sign.click()
    }

    /// Signs with `pin2` and answers the save panel it ends with.
    private func confirmSavePanel(
      afterSigningWith pin2: String, in app: XCUIApplication, window: XCUIElement
    ) {
      signWith(pin2, in: app, window: window)
      let panel = window.sheets.firstMatch
      XCTAssertTrue(
        panel.waitForExistence(timeout: UITestApp.appearTimeout),
        "no save panel after signing")
      let save = panel.buttons["Save"].firstMatch
      XCTAssertTrue(
        save.waitForExistence(timeout: UITestApp.appearTimeout),
        "the save panel has no Save button")
      save.click()
    }
  }

#endif
