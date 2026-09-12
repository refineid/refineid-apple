// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// Qualified signing with the virtual card through the visible GUI.
  @MainActor
  internal final class VirtualIDCardSigningUITests: XCTestCase {
    override internal func setUp() {
      super.setUp()
      continueAfterFailure = false
    }

    override internal func tearDown() {
      MainActor.assumeIsolated {
        XCUIApplication().terminate()
      }
      continueAfterFailure = true
      super.tearDown()
    }

    internal func testQualifiedDocumentSigningSucceedsThroughGUI() {
      let app = signingApp()

      fillSecure(UITestIdentifiers.signingPIN2, with: "123456", in: app)
      app.buttons[UITestIdentifiers.signingCommit].tap()

      XCTAssertTrue(
        app.buttons[UITestIdentifiers.signDocuments]
          .waitForExistence(timeout: UITestApp.appearTimeout),
        "successful signing did not return to the front page")
      XCTAssertFalse(
        app.buttons[UITestIdentifiers.signingCommit].exists,
        "the signing screen remained after success")
    }

    internal func testWrongSignaturePINConsumesOneAttemptThroughGUI() {
      let app = signingApp()

      fillSecure(UITestIdentifiers.signingPIN2, with: "000000", in: app)
      app.buttons[UITestIdentifiers.signingCommit].tap()
      assertSigningMessage(contains: "PIN 2 is incorrect", in: app)
      assertPIN2Attempts(4, in: app)
    }

    internal func testSignatureRetryFloorIsEnforcedThroughGUI() {
      let app = signingApp(pin2Attempts: 2)

      fillSecure(UITestIdentifiers.signingPIN2, with: "123456", in: app)
      app.buttons[UITestIdentifiers.signingCommit].tap()
      assertSigningMessage(contains: "Operation refused", in: app)
      assertPIN2Attempts(2, in: app)
    }

    internal func testMissingSignatureCertificateFailsThroughGUI() {
      let app = signingApp(signatureCertificate: "missing")

      fillSecure(UITestIdentifiers.signingPIN2, with: "123456", in: app)
      app.buttons[UITestIdentifiers.signingCommit].tap()
      assertSigningMessage(contains: "certificate is unavailable", in: app)
      assertPIN2Attempts(5, in: app)
    }

    internal func testCardRemovalBeforeSignatureDoesNotSpendAttempt() {
      let app = signingApp(fault: "cardRemovedDuringSignature")

      fillSecure(UITestIdentifiers.signingPIN2, with: "123456", in: app)
      app.buttons[UITestIdentifiers.signingCommit].tap()
      assertSigningMessage(contains: "connection was lost", in: app)
      assertPIN2Attempts(5, in: app)
    }

    internal func testLostResponseAfterSignaturePreservesCardExecution() {
      let app = signingApp(
        pin2Attempts: 4,
        fault: "responseLostAfterSignature")

      fillSecure(UITestIdentifiers.signingPIN2, with: "123456", in: app)
      app.buttons[UITestIdentifiers.signingCommit].tap()
      assertSigningMessage(contains: "connection was lost", in: app)
      assertPIN2Attempts(5, in: app)
    }

    internal func testSigningScreenIsLocalizedInFinnish() {
      assertSigningLocalization(
        language: "fi",
        labels: ["Allekirjoitustapa", "Yksittäin (PDF)", "Pakettina (ASiC-E)"])
    }

    internal func testSigningScreenIsLocalizedInSwedish() {
      assertSigningLocalization(
        language: "sv",
        labels: ["Signeringssätt", "Separat (PDF)", "Som paket (ASiC-E)"])
    }
  }
#endif
