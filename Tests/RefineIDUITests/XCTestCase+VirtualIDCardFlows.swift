// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// Virtual card journeys: scenarios, faults, credentials and destinations.
  extension XCTestCase {
    @MainActor
    internal func assertScenario(
      _ scenario: String,
      destination: VirtualIDCardUITestSupport.Destination
    ) {
      let app = UITestApp.launchVirtualCard()
      applyScenario(scenario, in: app)
      assertDestination(destination, scenario: scenario, in: app)
    }

    @MainActor
    internal func assertFaultPreset(_ preset: String) {
      let app = UITestApp.launchVirtualCard()
      openEditor(in: app)
      selectMenu(
        identifier: UITestIdentifiers.virtualCardFault,
        option: preset,
        in: app,
        optionIdentifier: "virtualCardFaultOption.\(preset)",
        scrolling: true)
      applyEditor(in: app)
    }

    @MainActor
    internal func assertCredentialJourney(_ journey: VirtualIDCardUITestSupport.CredentialJourney) {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-reader", in: app)
      openManagement(in: app)
      selectMenu(
        identifier: UITestIdentifiers.managementTask,
        option: journey.task,
        in: app)
      for field in journey.fields {
        fillSecure(field.identifier, with: field.value, in: app)
      }
      commit(action: journey.action, in: app)
      XCTAssertTrue(
        app.staticTexts[journey.outcome]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "\(journey.task) did not publish its outcome")
    }

    @MainActor
    internal func assertDestination(
      _ destination: VirtualIDCardUITestSupport.Destination,
      scenario: String,
      in app: XCUIApplication
    ) {
      let element: XCUIElement
      switch destination {
      case .cardAccessNumber:
        element = app.textFields[UITestIdentifiers.cardAccessNumberField]

      case .activation:
        element = app.buttons[UITestIdentifiers.managementActivate]

      case .readerIdentity:
        element = app.staticTexts[UITestIdentifiers.readerCardHolder]

      case .registeredIdentity:
        element = app.staticTexts[UITestIdentifiers.identityStatus]
      }
      XCTAssertTrue(
        element.waitForExistence(timeout: UITestApp.appearTimeout),
        "\(scenario) reached the wrong UI destination")
    }

    @MainActor
    internal func applyScenario(
      _ scenario: String,
      in app: XCUIApplication
    ) {
      openEditor(in: app)
      selectMenu(
        identifier: UITestIdentifiers.virtualCardScenario,
        option: scenario,
        in: app,
        optionIdentifier: "virtualCardScenarioOption.\(scenario)")
      applyEditor(in: app)
    }

    @MainActor
    internal func assertVirtualCardEditorLocalization(language: String) {
      let app = UITestApp.launch(
        language: language,
        arguments: ["--virtual-card", "absent"])
      let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
      XCTAssertTrue(
        overlay.waitForExistence(timeout: UITestApp.appearTimeout),
        "floating Virtual ID Card is missing in \(language)")
      XCTAssertFalse(overlay.label.isEmpty)
      XCTAssertNotEqual(
        overlay.label,
        "Virtual ID Card",
        "Virtual ID Card kept its English accessibility label in \(language)")

      openEditor(in: app)
      let scenario = app.descendants(matching: .any)[
        UITestIdentifiers.virtualCardScenario
      ]
      let fault = app.descendants(matching: .any)[
        UITestIdentifiers.virtualCardFault
      ]
      XCTAssertTrue(scenario.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(scenario.label.isEmpty)
      XCTAssertFalse(
        scenario.label.localizedCaseInsensitiveContains("Preset"),
        "scenario picker kept its English label in \(language)")

      scrollTo(fault, in: app)
      XCTAssertTrue(fault.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(fault.label.isEmpty)
      XCTAssertFalse(
        fault.label.localizedCaseInsensitiveContains("Fault"),
        "fault picker kept its English label in \(language)")
    }
  }
#endif
