// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import XCTest

  /// The remote pairing disconnect flow.
  ///
  /// After the holder removes the pairing the phone must reset its own
  /// UI to the Connect state and notify the remote side so its UI follows.
  @MainActor
  internal final class RemotePairingUITests: XCTestCase {
    /// Long enough for a first launch on the oldest supported hardware.
    private static let appearTimeout: TimeInterval = 15

    override internal func setUp() {
      super.setUp()
      continueAfterFailure = false
    }

    override internal func tearDown() {
      continueAfterFailure = true
      super.tearDown()
    }

    /// Remote access starts off: nothing may enable it before the holder.
    ///
    /// The toggle is the opt-in, so a fresh launch shows it off even with
    /// a registered identity present. Each launch decides from its own
    /// arguments, so no earlier run can leak an on state into this one.
    internal func testRemoteAccessDefaultsOff() {
      let app = UITestApp.launchVirtualCard(scenario: "registered-nfc")
      let toggle = element("remoteAccessToggle", in: app)
      XCTAssertTrue(
        toggle.waitForExistence(timeout: Self.appearTimeout),
        "the Remote Access toggle did not appear")
      let value = toggle.value
      let isOff =
        (value as? String == "0") || (value as? Int == 0)
        || (value as? Bool == false)
      XCTAssertTrue(isOff, "remote access was on without the holder opting in")
    }

    /// Flipping the toggle on enables remote access for the session.
    ///
    /// The switch is the opt-in, so tapping it must take effect without
    /// any other step. A dead toggle would leave the holder paired but
    /// silent, with no control showing why.
    internal func testToggleEnablesRemoteAccess() {
      let app = UITestApp.launchVirtualCard(scenario: "registered-nfc")
      let toggle = element("remoteAccessToggle", in: app)
      XCTAssertTrue(
        toggle.waitForExistence(timeout: Self.appearTimeout),
        "the Remote Access toggle did not appear")
      // The switch element spans the row; a center tap lands on the
      // label, so the tap goes to the switch control itself.
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
      XCTAssertTrue(
        toggle.waitForExistence(timeout: Self.appearTimeout),
        "the Remote Access toggle went missing after the tap")
      let value = toggle.value
      let isOn =
        (value as? String == "1") || (value as? Int == 1)
        || (value as? Bool == true)
      XCTAssertTrue(isOn, "tapping the toggle did not enable remote access")
    }

    /// Tapping Connect opens inline pairing controls.
    ///
    /// The holder row is served only where a card can be reached, so the
    /// run brings its own registered virtual identity instead of assuming
    /// the device antenna exists.
    internal func testConnectOpensInlinePairingControls() {
      let app = UITestApp.launchVirtualCard(scenario: "registered-nfc")
      let row = element(UITestIdentifiers.remoteAccessToggle, in: app)
      XCTAssertTrue(
        row.waitForExistence(timeout: Self.appearTimeout),
        "the remote card row did not appear")
      let connect = element("remoteConnectButton", in: app)
      XCTAssertTrue(
        connect.waitForExistence(timeout: Self.appearTimeout),
        "the remote card row offered no Connect action")
      connect.tap()
      XCTAssertTrue(
        element("pairingCodeEntry", in: app)
          .waitForExistence(timeout: Self.appearTimeout),
        "tapping Connect did not open inline pairing controls")
    }

    /// Removing the pairing resets the row to its initial state.
    ///
    /// The pretend pairing seeds the row's state, and the virtual card
    /// the row itself: neither the antenna nor a second device is needed.
    internal func testDisconnectResetsRowToConnectState() {
      let app = UITestApp.launch(arguments: [
        "--virtual-card", "registered-nfc", "--pretend-paired",
      ])
      let disconnect = app.descendants(matching: .any)["remoteDisconnectButton"]
        .firstMatch
      guard disconnect.waitForExistence(timeout: Self.appearTimeout) else {
        XCTFail("Remove-pairing control did not appear for a pretend-paired launch")
        return
      }
      disconnect.tap()

      let connect = app.descendants(matching: .any)["remoteConnectButton"]
        .firstMatch
      XCTAssertTrue(
        connect.waitForExistence(timeout: Self.appearTimeout),
        "Connect button did not reappear after Disconnect")
    }

    /// Finds a control by identifier whatever element type it took.
    private func element(
      _ identifier: String,
      in app: XCUIApplication
    ) -> XCUIElement {
      app.descendants(matching: .any)[identifier].firstMatch
    }
  }

#endif
