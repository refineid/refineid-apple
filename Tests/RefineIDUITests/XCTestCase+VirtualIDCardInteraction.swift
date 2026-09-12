// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// Low-level virtual card GUI interaction: menus, editors and typing.
  extension XCTestCase {
    internal enum AccessibilityFrameCapture {
      internal static let originXGroupIndex = 1
      internal static let originYGroupIndex = 2
      internal static let widthGroupIndex = 3
      internal static let heightGroupIndex = 4
      internal static let centerDivisor: CGFloat = 2
      internal static let maximumScrollAttempts = 8
    }

    @MainActor
    internal func openEditor(in app: XCUIApplication) {
      let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
      XCTAssertTrue(
        overlay.waitForExistence(timeout: UITestApp.appearTimeout),
        "floating Virtual ID Card is missing")
      overlay.tap()
      XCTAssertTrue(
        app.descendants(matching: .any)[UITestIdentifiers.virtualCardEditor]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "Virtual ID Card editor did not open")
    }

    @MainActor
    internal func applyEditor(in app: XCUIApplication) {
      let apply = app.buttons[UITestIdentifiers.virtualCardApply]
      XCTAssertTrue(apply.waitForExistence(timeout: UITestApp.appearTimeout))
      apply.tap()
      let editor = app.descendants(matching: .any)[
        UITestIdentifiers.virtualCardEditor
      ]
      let editorDismissed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"),
        object: editor)
      XCTAssertEqual(
        XCTWaiter.wait(for: [editorDismissed], timeout: UITestApp.appearTimeout),
        .completed,
        "Virtual ID Card editor did not close")
      let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
      let overlayReady = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == true AND hittable == true"),
        object: overlay)
      XCTAssertEqual(
        XCTWaiter.wait(for: [overlayReady], timeout: UITestApp.appearTimeout),
        .completed,
        "floating Virtual ID Card did not become ready")
    }

    @MainActor
    internal func selectMenu(
      identifier: String,
      option: String,
      in app: XCUIApplication
    ) {
      selectMenu(
        identifier: identifier,
        option: option,
        in: app,
        optionIdentifier: nil,
        scrolling: false
      )
    }

    @MainActor
    internal func selectMenu(
      identifier: String,
      option: String,
      in app: XCUIApplication,
      optionIdentifier: String?
    ) {
      selectMenu(
        identifier: identifier,
        option: option,
        in: app,
        optionIdentifier: optionIdentifier,
        scrolling: false
      )
    }

    @MainActor
    internal func selectMenu(
      identifier: String,
      option: String,
      in app: XCUIApplication,
      optionIdentifier: String?,
      scrolling: Bool
    ) {
      // A menu surfaces as its own control and again as its label; either opens it.
      let menu = app.descendants(matching: .any)[identifier].firstMatch
      if scrolling {
        scrollTo(menu, in: app)
      }
      XCTAssertTrue(
        menu.waitForExistence(timeout: UITestApp.appearTimeout),
        "\(identifier) menu is missing")
      menu.tap()
      let choice =
        optionIdentifier.map { identifier in
          app.descendants(matching: .any)[identifier].firstMatch
        } ?? app.buttons[option].firstMatch
      XCTAssertTrue(
        choice.waitForExistence(timeout: UITestApp.appearTimeout),
        "\(option) menu choice is missing")
      choice.tap()
    }

    @MainActor
    internal func connect(
      accessNumber: String,
      pin1: String,
      in app: XCUIApplication
    ) {
      let field = app.textFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: UITestApp.appearTimeout))
      focusAndType(field, value: accessNumber, in: app)
      let pin1Field = app.secureTextFields[UITestIdentifiers.pin1Field]
      XCTAssertTrue(pin1Field.waitForExistence(timeout: UITestApp.appearTimeout))
      focusAndType(pin1Field, value: pin1, in: app)
      let cache = app.buttons[UITestIdentifiers.primeStartButton]
      let enabled = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "enabled == true"),
        object: cache)
      XCTAssertEqual(
        XCTWaiter.wait(for: [enabled], timeout: UITestApp.appearTimeout),
        .completed,
        "Cache is disabled for complete CAN and PIN 1 entries")
      cache.tap()
    }

    @MainActor
    internal func openManagement(in app: XCUIApplication) {
      let key = app.buttons[UITestIdentifiers.pinManagementButton]
      XCTAssertTrue(key.waitForExistence(timeout: UITestApp.appearTimeout))
      key.tap()
      XCTAssertTrue(
        app.descendants(matching: .any)[UITestIdentifiers.managementTask]
          .waitForExistence(timeout: UITestApp.appearTimeout))
    }

    @MainActor
    internal func fillSecure(
      _ identifier: String,
      with value: String,
      in app: XCUIApplication
    ) {
      let field = app.secureTextFields[identifier]
      XCTAssertTrue(
        field.waitForExistence(timeout: UITestApp.appearTimeout),
        "\(identifier) field is missing")
      focusAndType(field, value: value, in: app)
    }

    @MainActor
    internal func focusAndType(
      _ field: XCUIElement,
      value: String,
      in app: XCUIApplication
    ) {
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == true AND hittable == true"),
        object: field)
      XCTAssertEqual(
        XCTWaiter.wait(for: [ready], timeout: UITestApp.appearTimeout),
        .completed,
        "\(field.identifier) did not become ready for input")
      app.activate()
      field.tap()
      let keyboard = app.keyboards.firstMatch
      XCTAssertTrue(
        keyboard.waitForExistence(timeout: UITestApp.appearTimeout),
        "The numeric keyboard did not appear for \(field.identifier)")
      let focused = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "hasKeyboardFocus == true"),
        object: field)
      XCTAssertEqual(
        XCTWaiter.wait(for: [focused], timeout: UITestApp.appearTimeout),
        .completed,
        "\(field.identifier) did not receive keyboard focus")
      field.typeText(value)
    }

    @MainActor
    internal func commit(action identifier: String, in app: XCUIApplication) {
      let action = app.buttons[identifier]
      scrollTo(action, in: app)
      XCTAssertTrue(action.isEnabled, "\(identifier) is disabled")
      action.tap()
      // iOS exposes nested outer and inner button nodes for each centered
      // alert action. Optimized element queries miss these nodes on iOS 26,
      // while a full accessibility snapshot materializes both identifiers.
      // Tapping waits for application quiescence, so this is an event barrier,
      // not a timing delay.
      let hierarchy = app.debugDescription
      let snapshot = XCTAttachment(string: hierarchy)
      snapshot.name = "Confirmation accessibility snapshot"
      snapshot.lifetime = .deleteOnSuccess
      add(snapshot)
      guard
        let center = accessibilityFrameCenter(
          of: UITestIdentifiers.managementConfirm,
          in: hierarchy
        )
      else {
        XCTFail("\(identifier) did not present its confirmation")
        return
      }
      let semanticConfirm = app.descendants(matching: .any)
        .matching(identifier: UITestIdentifiers.managementConfirm)
        .firstMatch
      if semanticConfirm.exists {
        semanticConfirm.tap()
        return
      }
      app.coordinate(withNormalizedOffset: .zero)
        .withOffset(center)
        .tap()
    }

    @MainActor
    internal func accessibilityFrameCenter(of identifier: String, in hierarchy: String) -> CGVector?
    {
      let number = #"-?[0-9]+(?:\.[0-9]+)?"#
      let escapedIdentifier = NSRegularExpression.escapedPattern(for: identifier)
      let pattern =
        #"\{\{("# + number + #"), ("# + number + #")\}, \{("#
        + number + #"), ("# + number + #")\}\}, identifier: '"#
        + escapedIdentifier + #"'"#
      guard
        let expression = try? NSRegularExpression(pattern: pattern),
        let match = expression.firstMatch(
          in: hierarchy,
          range: NSRange(hierarchy.startIndex..., in: hierarchy)
        )
      else {
        return nil
      }

      func value(at index: Int) -> CGFloat? {
        guard let range = Range(match.range(at: index), in: hierarchy) else { return nil }
        guard let parsed = Double(String(hierarchy[range])) else { return nil }
        return CGFloat(parsed)
      }

      guard
        let originX = value(at: AccessibilityFrameCapture.originXGroupIndex),
        let originY = value(at: AccessibilityFrameCapture.originYGroupIndex),
        let width = value(at: AccessibilityFrameCapture.widthGroupIndex),
        let height = value(at: AccessibilityFrameCapture.heightGroupIndex)
      else {
        return nil
      }
      return CGVector(
        dx: originX + width / AccessibilityFrameCapture.centerDivisor,
        dy: originY + height / AccessibilityFrameCapture.centerDivisor
      )
    }

    @MainActor
    internal func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
      for _ in 0..<AccessibilityFrameCapture.maximumScrollAttempts where !element.isHittable {
        app.swipeUp()
      }
    }
  }
#endif
