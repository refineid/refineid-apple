// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// The app's own diagnostics capture, fetched as text a failure can carry
/// out with it.
///
/// A UI test cannot read the app's memory, so it reads the screen the app
/// already draws for exactly this purpose. Every line on that screen
/// exists because its absence once made a failure unreadable: which tokens
/// are registered, what the watcher publishes, whether a prime is stored,
/// whether a signing credential is stored, and what the extensions left
/// behind.
///
/// Nothing on that screen is a secret. It counts and names states -- it
/// never shows a card access number, a PIN, a serial or a holder name --
/// which is why it is safe to attach whole.
@MainActor
internal enum AppDiagnostics {
  /// How long a screen takes to appear after a tap.
  private static let appearTimeout: TimeInterval = 15

  /// How many screens deep the capture is allowed to be buried.
  private static let popLimit: Int = 4

  /// Everything the diagnostics screen shows, or a line saying why not.
  ///
  /// Returns a note rather than failing: this is called to explain another
  /// failure, and a helper that can itself fail turns one diagnosis into
  /// two.
  internal static func text(from app: XCUIApplication) -> String {
    Self.popToRoot(in: app)
    let diagnostics = app.descendants(matching: .any)[UITestIdentifiers.diagnosticsButton]
    guard diagnostics.waitForExistence(timeout: Self.appearTimeout) else {
      return "diagnostics unavailable: the setup screen never came back"
    }
    diagnostics.tap()
    let capture = app.scrollViews.firstMatch
    guard capture.waitForExistence(timeout: Self.appearTimeout) else {
      return "diagnostics unavailable: the capture never appeared"
    }
    return capture.staticTexts.allElementsBoundByIndex
      .map(\.label)
      .joined(separator: "\n")
  }

  /// Returns to the setup screen, however deep the run left the stack.
  ///
  /// The capture is reached from the root, and a test that failed on the
  /// priming screen is two screens away from it.
  private static func popToRoot(in app: XCUIApplication) {
    var remaining = Self.popLimit
    while remaining > 0 {
      let back = app.navigationBars.buttons.firstMatch
      guard back.exists, back.isHittable else { return }
      back.tap()
      remaining -= 1
    }
  }
}
