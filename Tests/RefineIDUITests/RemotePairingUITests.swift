// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import XCTest

  /// The holder's Remote Access opt-in flow.
  ///
  /// The toggle starts off; turning it on walks through the two
  /// explanations before any system prompt may appear, and turning it
  /// off wipes every remote trace. The permission tests run on device
  /// only: the simulator never shows the system prompt.
  @MainActor
  internal final class RemotePairingUITests: XCTestCase {
    // MARK: Static Properties

    /// Long enough for a first launch on the oldest supported hardware.
    private static let appearTimeout: TimeInterval = 15

    private static let allowTitles = ["Allow", "Salli", "Tillåt"]
    private static let denyTitles = ["Don't Allow", "Älä salli", "Tillåt inte"]
    private static let settingsBackTapLimit = 6
    private static let switchSettleTimeout: TimeInterval = 3

    // MARK: Static Functions

    private static func isLocalNetworkPrompt(_ prompt: XCUIElement) -> Bool {
      let text = prompt.staticTexts.allElementsBoundByIndex
        .map(\.label)
        .joined(separator: " ")
        .lowercased()
      return text.contains("local network")
        || text.contains("lähiverk")
        || text.contains("lokala nätverk")
    }

    // MARK: Functions

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
      XCTAssertTrue(isOff(toggle), "remote access was on without the holder opting in")
    }

    /// Turning the toggle on walks the education flow to the code boxes.
    ///
    /// The local-network explanation comes first with a lone OK, then
    /// the notifications explanation; only then may the switch stay on
    /// and the pairing-code boxes appear for the requester's code.
    internal func testToggleOnCompletesEducationFlow() {
      let app = UITestApp.launchVirtualCard(scenario: "registered-nfc")
      flipToggle(in: app)
      confirmAlert(titled: "Remote Card Use", in: app)
      confirmAlert(titled: "Allow Notifications", in: app)
      let toggle = element("remoteAccessToggle", in: app)
      XCTAssertTrue(isOn(toggle), "the toggle did not stay on after the explanations")
      XCTAssertTrue(
        element("pairingCodeEntry", in: app)
          .waitForExistence(timeout: Self.appearTimeout),
        "the pairing-code boxes did not appear for the unpaired holder")
    }

    /// Turning the toggle off wipes every remote trace at once.
    ///
    /// Off means off: the switch, the code boxes, and the stored
    /// pairings all go, with no separate disconnect step.
    internal func testToggleOffWipesRemoteState() {
      let app = UITestApp.launchVirtualCard(scenario: "registered-nfc")
      flipToggle(in: app)
      confirmAlert(titled: "Remote Card Use", in: app)
      confirmAlert(titled: "Allow Notifications", in: app)
      flipToggle(in: app)
      let toggle = element("remoteAccessToggle", in: app)
      XCTAssertTrue(isOff(toggle), "the toggle did not turn back off")
      XCTAssertFalse(
        element("pairingCodeEntry", in: app).exists,
        "the pairing-code boxes survived turning remote access off")
    }

    /// Denying local-network access keeps Remote Access turned off.
    ///
    /// Device only. The Settings switch decides the permission first
    /// (reinstalls do not reset it); after the denial the app returns
    /// to the main screen with the switch off and a Settings redirect.
    internal func testLocalNetworkDenialKeepsRemoteOff() throws {
      try requireDevice()
      setSystemLocalNetworkAccess(enabled: false)
      let app = UITestApp.launchVirtualCard(scenario: "registered-nfc")
      flipToggle(in: app)
      confirmAlert(titled: "Remote Card Use", in: app)
      _ = answerSystemPrompt(titles: Self.denyTitles, in: app, within: 4)
      let denied = app.alerts["Local Network Access Is Off"]
      XCTAssertTrue(
        denied.waitForExistence(timeout: Self.appearTimeout),
        "no redirect followed the denied local-network access")
      denied.buttons["Cancel"].tap()
      XCTAssertTrue(
        isOff(element("remoteAccessToggle", in: app)),
        "remote access stayed on after the holder denied access")
    }

    /// Allowing local-network access completes the flow to the code boxes.
    ///
    /// Device only. The Settings switch decides the permission first;
    /// after it the notifications explanation follows then the code
    /// boxes appear, leaving the phone as the test found it.
    internal func testLocalNetworkAllowShowsCodeEntry() throws {
      try requireDevice()
      setSystemLocalNetworkAccess(enabled: true)
      let app = UITestApp.launchVirtualCard(scenario: "registered-nfc")
      flipToggle(in: app)
      confirmAlert(titled: "Remote Card Use", in: app)
      _ = answerSystemPrompt(titles: Self.allowTitles, in: app, within: 4)
      confirmAlert(titled: "Allow Notifications", in: app)
      // The notifications decision is the holder's own; declining only
      // costs the backgrounded case, so the prompt is left standing.
      let toggle = element("remoteAccessToggle", in: app)
      XCTAssertTrue(isOn(toggle), "the toggle did not stay on after allowing access")
      XCTAssertTrue(
        element("pairingCodeEntry", in: app)
          .waitForExistence(timeout: Self.appearTimeout),
        "the pairing-code boxes did not appear after allowing access")
    }

    /// Skips permission tests where no system prompt can appear.
    private func requireDevice() throws {
      if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
        throw XCTSkip("the system local-network prompt needs a device")
      }
    }

    /// Taps the switch control itself, not the spanning row.
    private func flipToggle(in app: XCUIApplication) {
      let toggle = element("remoteAccessToggle", in: app)
      XCTAssertTrue(
        toggle.waitForExistence(timeout: Self.appearTimeout),
        "the Remote Access toggle did not appear")
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Confirms one of the app's own single-button explanations.
    private func confirmAlert(titled title: String, in app: XCUIApplication) {
      let alert = app.alerts[title]
      XCTAssertTrue(
        alert.waitForExistence(timeout: Self.appearTimeout),
        "the \(title) explanation never appeared")
      alert.buttons["OK"].tap()
    }

    /// Answers the system local-network prompt with the first title found.
    ///
    /// The prompt only appears for undecided permission; the Settings
    /// switch normally decides it first, so absence is the routine case.
    private func answerSystemPrompt(
      titles: [String],
      in app: XCUIApplication,
      within seconds: TimeInterval
    ) -> Bool {
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      let deadline = Date().addingTimeInterval(seconds)
      while Date() < deadline {
        for owner in [app, springboard] {
          for prompt in [owner.alerts.firstMatch, owner.sheets.firstMatch]
          where prompt.exists && Self.isLocalNetworkPrompt(prompt) {
            for title in titles where prompt.buttons[title].exists {
              prompt.buttons[title].tap()
              return true
            }
          }
        }
        app.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
      return false
    }

    /// Sets this app's system local-network switch to the wanted state.
    private func setSystemLocalNetworkAccess(enabled: Bool) {
      let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
      settings.launch()
      XCTAssertTrue(
        settings.wait(for: .runningForeground, timeout: Self.appearTimeout),
        "Settings never reached the foreground")
      backToSettingsRoot(settings)
      openSettingsCell(
        titles: [
          "Privacy & Security",
          "Tietosuoja ja suojaus",
          "Integritet och säkerhet",
        ],
        in: settings)
      openSettingsCell(titles: ["Local Network", "Lähiverkko", "Lokalt nätverk"], in: settings)
      let row = settings.descendants(matching: .any)["RefineID"].firstMatch
      XCTAssertTrue(
        row.waitForExistence(timeout: Self.appearTimeout),
        "RefineID is missing from the system Local Network list")
      let toggle = row.descendants(matching: .switch).firstMatch
      XCTAssertTrue(
        toggle.waitForExistence(timeout: Self.appearTimeout),
        "the RefineID system switch never appeared")
      if isOn(toggle) != enabled {
        toggle.tap()
      }
      let deadline = Date().addingTimeInterval(Self.switchSettleTimeout)
      while Date() < deadline, isOn(toggle) != enabled {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
      XCTAssertEqual(
        isOn(toggle),
        enabled,
        "the RefineID system switch reads \(String(describing: toggle.value))")
      let shot = XCTAttachment(screenshot: settings.screenshot())
      shot.name = "local-network-switch"
      shot.lifetime = .keepAlways
      add(shot)
      // Launching the app under test foregrounds it again; Settings
      // stays suspended and needs no teardown.
    }

    /// Returns Settings to its root list; it reopens where left off.
    private func backToSettingsRoot(_ settings: XCUIApplication) {
      for _ in 0..<Self.settingsBackTapLimit {
        let back = settings.navigationBars.firstMatch.buttons.firstMatch
        guard back.exists else { return }
        back.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }

    /// Opens the first matching Settings cell, scrolling until it shows.
    private func openSettingsCell(titles: [String], in settings: XCUIApplication) {
      let deadline = Date().addingTimeInterval(Self.appearTimeout)
      while Date() < deadline {
        for title in titles {
          let cell = settings.descendants(matching: .any)[title].firstMatch
          if cell.exists {
            cell.tap()
            return
          }
        }
        settings.swipeUp()
      }
      XCTFail(
        "Settings cell \(titles.first ?? "") never appeared: "
          + String(settings.debugDescription.prefix(1_500))
      )
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
      let value = toggle.value
      return (value as? String == "1") || (value as? Int == 1)
        || (value as? Bool == true)
    }

    private func isOff(_ toggle: XCUIElement) -> Bool {
      let value = toggle.value
      return (value as? String == "0") || (value as? Int == 0)
        || (value as? Bool == false)
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
