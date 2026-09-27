// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

#if os(macOS)
  @MainActor
  internal final class ScsSettingsUITests: XCTestCase {
    internal func testLocalWebSigningStartsDisabledInSettings() throws {
      try check(language: "en", topic: "Signing Service", label: "Signature Creation Service")
    }

    internal func testFinnishServiceName() throws {
      try check(
        language: "fi", topic: "Allekirjoituspalvelu",
        label: "Allekirjoituspalvelu (Signature Creation Service)")
    }

    internal func testSwedishServiceName() throws {
      try check(
        language: "sv", topic: "Signeringstj\u{00E4}nst",
        label: "Signeringstj\u{00E4}nst (Signature Creation Service)")
    }

    private func check(language: String, topic: String, label: String) throws {
      let app = XCUIApplication()
      app.launchArguments = ["-fi.refineid.scs.enabled", "NO", "-AppleLanguages", "(\(language))"]
      app.launch()
      defer { app.terminate() }
      app.typeKey(",", modifierFlags: .command)
      let tab = app.buttons[topic]
      XCTAssertTrue(tab.waitForExistence(timeout: 5))
      tab.click()
      XCTAssertTrue(app.staticTexts[label].firstMatch.waitForExistence(timeout: 5))
      let toggle = app.switches["scsEnabled"]
      XCTAssertTrue(toggle.waitForExistence(timeout: 5))
      let value = try XCTUnwrap(toggle.value)
      XCTAssertEqual(String(describing: value), "0")
      XCTAssertTrue(toggle.isEnabled)
    }
  }
#endif
