// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import XCTest

  /// The native Settings page renders the service address without its HTTP prefix.
  @MainActor
  internal final class TimestampSettingsUITests: XCTestCase {
    private enum Navigation {
      static let maximumBackSteps = 8
      static let maximumScrolls = 12
      static let defaultAddress = "timestamp.sectigo.com/qualified"
    }

    internal func testNativeSettingsShowsAddressWithoutHttp() {
      continueAfterFailure = false
      let app = UITestApp.launch(arguments: ["--virtual-card", "absent"])
      app.terminate()
      let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
      settings.launchArguments = ["-AppleLanguages", "(en)"]
      settings.launch()
      defer { settings.terminate() }
      openAppSettings(settings)
      let address = settings.textFields.firstMatch
      XCTAssertTrue(address.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertEqual(address.value as? String, Navigation.defaultAddress)
      let capture = XCTAttachment(screenshot: settings.screenshot())
      capture.name = "timestamp-settings"
      capture.lifetime = .keepAlways
      add(capture)

    }

    private func openAppSettings(_ settings: XCUIApplication) {
      if settings.navigationBars["RefineID"].exists { return }
      for _ in .zero..<Navigation.maximumBackSteps {
        if settings.navigationBars["Settings"].exists { break }
        let back = settings.navigationBars.buttons.firstMatch
        guard back.exists else { break }
        back.tap()
      }
      let apps = settings.buttons["com.apple.settings.apps"]
      reveal(apps, in: settings)
      apps.tap()
      let row = settings.buttons["fi.refineid.ReFineID"]
      reveal(row, in: settings)
      row.tap()
      XCTAssertTrue(
        settings.navigationBars["RefineID"].waitForExistence(timeout: UITestApp.appearTimeout))
    }

    private func reveal(_ element: XCUIElement, in settings: XCUIApplication) {
      for _ in .zero..<Navigation.maximumScrolls {
        if element.exists, element.isHittable { return }
        settings.swipeUp()
      }
      XCTAssertTrue(element.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertTrue(element.isHittable)
    }
  }
#endif
