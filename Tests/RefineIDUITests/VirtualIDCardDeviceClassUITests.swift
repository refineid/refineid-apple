// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// The Virtual ID Card editor offers each device class only the
  /// transports that class has: near-field states exist on iPhone and
  /// nowhere else.
  @MainActor
  internal final class VirtualIDCardDeviceClassUITests: XCTestCase {
    private static let appearTimeout: TimeInterval = 10

    /// Whether the device under test offers near-field states.
    private var offersNearField: Bool {
      UIDevice.current.userInterfaceIdiom == .phone
    }

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

    internal func testTransportControlsFollowDeviceClass() {
      let app = UITestApp.launchVirtualCard()
      openEditor(in: app)

      let transport = app.descendants(matching: .any)["virtualCardTransport"]
      let accessNumber = app.descendants(matching: .any)["virtualCardCAN"]
      XCTAssertEqual(
        transport.exists,
        offersNearField,
        "transport choice does not match the device class")
      XCTAssertEqual(
        accessNumber.exists,
        offersNearField,
        "CAN entry does not match the device class")

      let pin1Stored = app.switches["virtualCardPIN1Stored"]
      scrollTo(pin1Stored, in: app)
      XCTAssertTrue(pin1Stored.waitForExistence(timeout: Self.appearTimeout))
      XCTAssertEqual(
        app.descendants(matching: .any)["virtualCardStoredCAN"].exists,
        offersNearField,
        "stored CAN does not match the device class")
      XCTAssertEqual(
        app.descendants(matching: .any)["virtualCardConnectedCAN"].exists,
        offersNearField,
        "connected CAN does not match the device class")
    }

    internal func testScenarioChoicesFollowDeviceClass() {
      let app = UITestApp.launchVirtualCard()
      openEditor(in: app)

      let scenario = app.descendants(
        matching: .any)[UITestIdentifiers.virtualCardScenario]
      XCTAssertTrue(scenario.waitForExistence(timeout: Self.appearTimeout))
      scenario.tap()
      let reader = app.descendants(
        matching: .any)["virtualCardScenarioOption.activated-reader"]
        .firstMatch
      XCTAssertTrue(reader.waitForExistence(timeout: Self.appearTimeout))
      XCTAssertEqual(
        app.descendants(
          matching: .any)["virtualCardScenarioOption.factory-fresh-nfc"]
          .firstMatch.exists,
        offersNearField,
        "NFC scenario offer does not match the device class")
      reader.tap()
    }

    internal func testFaultChoicesFollowDeviceClass() {
      let app = UITestApp.launchVirtualCard()
      openEditor(in: app)

      let fault = app.descendants(
        matching: .any)[UITestIdentifiers.virtualCardFault]
      scrollTo(fault, in: app)
      XCTAssertTrue(fault.waitForExistence(timeout: Self.appearTimeout))
      fault.tap()
      let readerFault = app.descendants(
        matching: .any)["virtualCardFaultOption.readerFailsCounterQuery"]
        .firstMatch
      XCTAssertTrue(readerFault.waitForExistence(timeout: Self.appearTimeout))
      XCTAssertEqual(
        app.descendants(
          matching:
            .any)["virtualCardFaultOption.nfcDisconnectBeforeConnection"]
          .firstMatch.exists,
        offersNearField,
        "NFC fault offer does not match the device class")
      readerFault.tap()
    }

  }

#endif
