// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// The setup screen, driven the way a holder drives it: open the
/// authentication prompt, enter the access number, then start the
/// single identity-minting operation.
///
/// It is a page object rather than a test so that the priming test can
/// bring a device up to a known state without depending on the setup test
/// having run first. Cross-test ordering is not something XCTest promises,
/// and a device round trip is too expensive to spend discovering that.
///
/// Nothing here attaches, prints or returns the digits it is given.
@MainActor
internal enum CardSetupScreen {
  /// How long a control takes to appear after launch.
  private static let appearTimeout: TimeInterval = 10

  /// How long the optional prompt detour may take; a device that
  /// already holds an identity offers no prompt at all.
  private static let optionalTimeout: TimeInterval = 2
  private static let deleteCharacterCount = 32

  /// Opens the authentication prompt and enters the access number.
  ///
  /// A device that already holds an identity offers neither, and the
  /// entry below reports that on its own; replacing a card is the
  /// explicit destructive action on the screen, not something
  /// automation should do implicitly.
  internal static func enterCredentials(
    cardAccessNumber: String?,
    in app: XCUIApplication
  ) -> Bool {
    if let cardAccessNumber {
      Self.openAuthenticationPrompt(in: app)
      guard
        Self.enter(
          cardAccessNumber,
          field: UITestIdentifiers.cardAccessNumberField,
          in: app
        )
      else { return false }
    }
    return true
  }

  /// Opens the setup authentication prompt when the setup screen offers it.
  private static func openAuthenticationPrompt(in app: XCUIApplication) {
    let auth = app.descendants(matching: .any)[UITestIdentifiers.setupAuthenticate]
    guard
      auth.waitForExistence(timeout: Self.optionalTimeout),
      auth.isHittable
    else {
      return
    }
    auth.tap()
  }

  /// Enters one value into a field that is there until an identity is.
  private static func enter(
    _ digits: String,
    field fieldIdentifier: String,
    in app: XCUIApplication
  ) -> Bool {
    let field = app.descendants(matching: .any)[fieldIdentifier]
    guard field.waitForExistence(timeout: Self.appearTimeout), field.isHittable else {
      return false
    }
    field.tap()
    field.typeText(
      String(
        repeating: XCUIKeyboardKey.delete.rawValue,
        count: Self.deleteCharacterCount))
    field.typeText(digits)

    if fieldIdentifier == UITestIdentifiers.cardAccessNumberField {
      // A complete entry starts the hold by itself and dismisses the
      // prompt with it; a dismissed prompt means the entry landed.
      guard field.exists else { return true }
      return (field.value as? String) == digits
    }
    return true
  }
}
