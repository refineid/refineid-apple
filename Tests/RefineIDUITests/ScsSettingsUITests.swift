// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

#if os(macOS)
  @MainActor
  internal final class ScsSettingsUITests: XCTestCase {
    internal func testLocalWebSigningStartsDisabledInSettings() throws {
      let app = XCUIApplication()
      app.launchArguments = ["-fi.refineid.scs.enabled", "NO", "-AppleLanguages", "(en)"]
      app.launch()
      defer { app.terminate() }
      app.typeKey(",", modifierFlags: .command)
      let tab = app.buttons["Web Signing"]
      XCTAssertTrue(tab.waitForExistence(timeout: 5))
      tab.click()
      let toggle = app.switches["scsEnabled"]
      XCTAssertTrue(toggle.waitForExistence(timeout: 5))
      let value = try XCTUnwrap(toggle.value)
      XCTAssertEqual(String(describing: value), "0")
      XCTAssertTrue(toggle.isEnabled)
    }
  }
#endif
