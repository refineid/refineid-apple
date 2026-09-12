// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// Virtual card signing journeys through the visible GUI.
  extension XCTestCase {
    internal enum SigningCardSetup {
      internal static let defaultPIN2Attempts = 5
    }

    @MainActor
    internal func assertSigningLocalization(
      language: String,
      labels: [String]
    ) {
      let app = UITestApp.launch(
        language: language,
        arguments: ["--virtual-card", "absent"])
      configureSigningCard(in: app)
      openSigning(in: app)

      let commit = app.buttons[UITestIdentifiers.signingCommit]
      XCTAssertTrue(commit.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertFalse(commit.label.isEmpty)
      XCTAssertNotEqual(
        commit.label,
        "Sign documents",
        "signing action remained English in \(language)")
      for label in labels {
        XCTAssertTrue(
          app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch.waitForExistence(timeout: UITestApp.appearTimeout),
          "missing \(language) signing label: \(label)")
      }
    }

    @MainActor
    internal func signingApp() -> XCUIApplication {
      signingApp(
        pin2Attempts: SigningCardSetup.defaultPIN2Attempts,
        signatureCertificate: nil,
        fault: nil
      )
    }

    @MainActor
    internal func signingApp(pin2Attempts: Int) -> XCUIApplication {
      signingApp(
        pin2Attempts: pin2Attempts,
        signatureCertificate: nil,
        fault: nil
      )
    }

    @MainActor
    internal func signingApp(signatureCertificate: String?) -> XCUIApplication {
      signingApp(
        pin2Attempts: SigningCardSetup.defaultPIN2Attempts,
        signatureCertificate: signatureCertificate,
        fault: nil
      )
    }

    @MainActor
    internal func signingApp(fault: String?) -> XCUIApplication {
      signingApp(
        pin2Attempts: SigningCardSetup.defaultPIN2Attempts,
        signatureCertificate: nil,
        fault: fault
      )
    }

    @MainActor
    internal func signingApp(pin2Attempts: Int, fault: String?) -> XCUIApplication {
      signingApp(
        pin2Attempts: pin2Attempts,
        signatureCertificate: nil,
        fault: fault
      )
    }

    @MainActor
    internal func signingApp(
      pin2Attempts: Int,
      signatureCertificate: String?,
      fault: String?
    ) -> XCUIApplication {
      let app = UITestApp.launchVirtualCard()
      configureSigningCard(
        in: app,
        pin2Attempts: pin2Attempts,
        signatureCertificate: signatureCertificate,
        fault: fault)
      openSigning(in: app)
      return app
    }

    @MainActor
    internal func configureSigningCard(in app: XCUIApplication) {
      configureSigningCard(
        in: app,
        pin2Attempts: SigningCardSetup.defaultPIN2Attempts,
        signatureCertificate: nil,
        fault: nil
      )
    }

    @MainActor
    internal func configureSigningCard(
      in app: XCUIApplication,
      pin2Attempts: Int,
      signatureCertificate: String?,
      fault: String?
    ) {
      openEditor(in: app)
      selectMenu(
        identifier: UITestIdentifiers.virtualCardScenario,
        option: "activated-reader",
        in: app,
        optionIdentifier: "virtualCardScenarioOption.activated-reader")

      if pin2Attempts != SigningCardSetup.defaultPIN2Attempts {
        let stepper = app.steppers[UITestIdentifiers.virtualCardPIN2Attempts]
        scrollTo(stepper, in: app)
        XCTAssertTrue(stepper.waitForExistence(timeout: UITestApp.appearTimeout))
        for _ in pin2Attempts..<SigningCardSetup.defaultPIN2Attempts {
          stepper.buttons.firstMatch.tap()
        }
      }

      if let signatureCertificate {
        selectMenu(
          identifier: "virtualCardSignatureCertificate",
          option: signatureCertificate,
          in: app,
          optionIdentifier:
            "virtualCardCertificateOption.\(signatureCertificate)",
          scrolling: true)
      }

      let pending = app.buttons["virtualCardSigningPending"]
      scrollTo(pending, in: app)
      XCTAssertTrue(pending.waitForExistence(timeout: UITestApp.appearTimeout))
      pending.tap()

      if let fault {
        selectMenu(
          identifier: UITestIdentifiers.virtualCardFault,
          option: fault,
          in: app,
          optionIdentifier: "virtualCardFaultOption.\(fault)",
          scrolling: true)
      }
      applyEditor(in: app)
    }

    @MainActor
    internal func openSigning(in app: XCUIApplication) {
      let link = app.buttons[UITestIdentifiers.signDocuments]
      XCTAssertTrue(link.waitForExistence(timeout: UITestApp.appearTimeout))
      link.tap()
      XCTAssertTrue(
        app.secureTextFields[UITestIdentifiers.signingPIN2]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "pending virtual document was not prepared")
    }

    @MainActor
    internal func assertSigningMessage(
      contains expected: String,
      in app: XCUIApplication
    ) {
      let message = app.descendants(matching: .any)[
        UITestIdentifiers.signingMessage
      ]
      XCTAssertTrue(message.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertTrue(
        message.label.localizedCaseInsensitiveContains(expected),
        "unexpected signing feedback: \(message.label)")
    }

    @MainActor
    internal func assertPIN2Attempts(
      _ expected: Int,
      in app: XCUIApplication
    ) {
      openEditor(in: app)
      let stepper = app.steppers[UITestIdentifiers.virtualCardPIN2Attempts]
      scrollTo(stepper, in: app)
      XCTAssertTrue(stepper.waitForExistence(timeout: UITestApp.appearTimeout))
      XCTAssertTrue(
        (stepper.value as? String ?? "").contains("\(expected)"),
        "PIN 2 counter is \(stepper.value ?? "missing"), expected \(expected)")
      app.buttons[UITestIdentifiers.virtualCardApply].tap()
    }
  }
#endif
