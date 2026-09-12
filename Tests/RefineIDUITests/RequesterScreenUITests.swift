// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && !REFINEID_LOCAL_CARD

  import XCTest

  /// The screen a device with no card of its own offers.
  ///
  /// Such a device can do exactly two things: verify a document, which
  /// touches no card, and borrow one from a paired phone. Everything else
  /// the app can do needs a card this device can never reach, and a
  /// control that can never open describes the app as broken rather than
  /// the device as different.
  ///
  /// The build without `REFINEID_LOCAL_CARD` is the one that runs here, so
  /// these tests exist only in it. On a build that talks to its own card
  /// the same screen carries the setup this bundle's other tests drive.
  @MainActor
  internal final class RequesterScreenUITests: XCTestCase {
    /// Long enough for a first launch on the oldest supported hardware.
    private static let appearTimeout: TimeInterval = 15

    /// How long a code may take to be drawn once its sheet is up.
    ///
    /// Generating it asks nothing of a network or a peer, so this bounds
    /// a local drawing rather than a conversation.
    private static let codeTimeout: TimeInterval = 10

    override internal func setUp() {
      super.setUp()
      continueAfterFailure = false
    }

    override internal func tearDown() {
      continueAfterFailure = true
      super.tearDown()
    }

    /// The screen offers what the device can do, and nothing else.
    internal func testRequesterOffersOnlyTheRoutesItCanOpen() {
      let app = UITestApp.launch()
      XCTAssertTrue(
        element(UITestIdentifiers.connectRemoteReader, in: app)
          .waitForExistence(timeout: Self.appearTimeout),
        "the requester cannot borrow a card")
      XCTAssertTrue(
        element(UITestIdentifiers.verifyDocuments, in: app).exists,
        "verifying a document needs no card and must stay offered")
      let sign = element(UITestIdentifiers.signDocuments, in: app)
      XCTAssertTrue(sign.exists, "signing is offered once a paired identity exists")
      XCTAssertFalse(sign.isEnabled, "signing stays closed until a person is named")

      for absent in [
        UITestIdentifiers.pinManagementButton,
        UITestIdentifiers.remoteCard,
        UITestIdentifiers.cardAccessNumberField,
        UITestIdentifiers.pin1Field,
      ] {
        XCTAssertFalse(
          element(absent, in: app).exists,
          "\(absent) reaches a card this device does not have")
      }
    }

    /// A stored pairing is asked, rather than replaced with a new one.
    ///
    /// This once went straight to the code whatever was stored, because a
    /// pairing the peer had forgotten left the tap waiting for an answer
    /// that never came and the button looked dead. The answer now comes,
    /// so the pairing is asked; one the peer no longer honours still ends
    /// at the code, by way of ``needsFreshPairing``.
    internal func testConnectRemoteReaderAsksTheStoredPairing() {
      let app = UITestApp.launch(arguments: ["--pretend-paired"])
      let connect = element(UITestIdentifiers.connectRemoteReader, in: app)
      XCTAssertTrue(connect.waitForExistence(timeout: Self.appearTimeout))
      connect.tap()

      XCTAssertFalse(
        element(UITestIdentifiers.pairingCode, in: app)
          .waitForExistence(timeout: Self.codeTimeout),
        "a stored pairing was replaced with a fresh code instead of asked")
    }

    /// One tap reaches the code, and closing it leaves the screen whole.
    ///
    /// Completing the pairing needs a phone to read the code, so the walk
    /// stops where the code is on screen. Everything up to there is the
    /// stretch that has been failing.
    internal func testConnectRemoteReaderShowsTheCodeDirectlyAndCloses() {
      let app = UITestApp.launch()
      let connect = element(UITestIdentifiers.connectRemoteReader, in: app)
      XCTAssertTrue(connect.waitForExistence(timeout: Self.appearTimeout))
      connect.tap()

      XCTAssertTrue(
        element(UITestIdentifiers.pairingCode, in: app)
          .waitForExistence(timeout: Self.codeTimeout),
        "the code a phone scans did not appear")
      XCTAssertFalse(
        element(UITestIdentifiers.pairPhone, in: app).exists,
        "a page stands between the tap and the code")
      XCTAssertEqual(
        app.state, .runningForeground,
        "the app did not survive showing the code")

      // The code is the whole screen and carries no control of its own, so
      // it is put away the way the platform puts a sheet away.
      XCTAssertFalse(
        element(UITestIdentifiers.closePairing, in: app).exists,
        "the code screen grew a control it does not need")
      dismissSheet(in: app)

      XCTAssertTrue(
        element(UITestIdentifiers.verifyDocuments, in: app)
          .waitForExistence(timeout: Self.appearTimeout),
        "closing the code left no screen behind it")
      XCTAssertTrue(
        element(UITestIdentifiers.connectRemoteReader, in: app).exists,
        "the route back to a card did not come back")
      XCTAssertEqual(
        app.state, .runningForeground,
        "the app did not survive closing the code")
    }

    /// A document is verified without a card, a phone, or an identity.
    internal func testVerifyOpensAndReturns() {
      let app = UITestApp.launch()
      let verify = element(UITestIdentifiers.verifyDocuments, in: app)
      XCTAssertTrue(verify.waitForExistence(timeout: Self.appearTimeout))
      verify.tap()

      let bar = app.navigationBars.firstMatch
      XCTAssertTrue(
        bar.waitForExistence(timeout: Self.appearTimeout),
        "document verification did not open")

      let back = bar.buttons.firstMatch
      XCTAssertTrue(back.waitForExistence(timeout: Self.appearTimeout))
      back.tap()

      XCTAssertTrue(
        element(UITestIdentifiers.connectRemoteReader, in: app)
          .waitForExistence(timeout: Self.appearTimeout),
        "leaving verification did not return to the two routes")
      XCTAssertEqual(
        app.state, .runningForeground,
        "the app did not survive opening verification")
    }

    /// Puts a sheet away the way a hand does.
    ///
    /// A sheet with nothing but content on it is dragged down; one shown
    /// as a card over a dimmed screen also goes when the screen behind it
    /// is touched. Both gestures are tried because which one applies is
    /// the platform's choice, not the app's.
    private func dismissSheet(in app: XCUIApplication) {
      let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
      let past = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.4))
      top.press(forDuration: 0.05, thenDragTo: past)

      let back = element(UITestIdentifiers.connectRemoteReader, in: app)
      guard !back.waitForExistence(timeout: Self.codeTimeout) else { return }
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
    }

    /// Finds a control by identifier whatever element type it took.
    ///
    /// A row that carries an identifier may report as a button, a cell or
    /// a static text depending on how the platform lays the form out, and
    /// the test is asking about the route rather than the shape. One
    /// control can also surface as a wrapper and its label both, so the
    /// first match is taken: the question is whether the route is there,
    /// not how many layers draw it.
    private func element(
      _ identifier: String,
      in app: XCUIApplication
    ) -> XCUIElement {
      app.descendants(matching: .any)[identifier].firstMatch
    }
  }

#endif
