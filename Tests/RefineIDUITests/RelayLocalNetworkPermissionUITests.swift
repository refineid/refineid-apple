// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import XCTest

  /// Grants only the system Local Network prompt needed by the encrypted
  /// iPhone-to-Mac card relay.
  ///
  /// The test is idempotent after permission has already been decided.
  @MainActor
  internal final class RelayLocalNetworkPermissionUITests: XCTestCase {
    // MARK: Static Functions

    private static func takeAffirmativeAction(in prompt: XCUIElement) -> Bool {
      for title in ["Allow", "Salli", "Tillåt"]
      where prompt.buttons[title].exists {
        prompt.buttons[title].tap()
        return true
      }
      return false
    }

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

    internal func testGrantsRelayPermissionIfPresented() {
      let app = XCUIApplication()
      let monitor = addUIInterruptionMonitor(withDescription: "Local Network") {
        prompt in
        guard Self.isLocalNetworkPrompt(prompt) else { return false }
        return Self.takeAffirmativeAction(in: prompt)
      }
      defer { removeUIInterruptionMonitor(monitor) }

      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      app.launch()
      app.tap()

      let deadline = Date().addingTimeInterval(12)
      while Date() < deadline {
        for owner in [app, springboard] {
          for prompt in [owner.alerts.firstMatch, owner.sheets.firstMatch]
          where prompt.exists && Self.isLocalNetworkPrompt(prompt) {
            if Self.takeAffirmativeAction(in: prompt) { return }
          }
        }
        app.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }
  }
#endif
