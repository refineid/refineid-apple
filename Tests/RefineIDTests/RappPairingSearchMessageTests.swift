// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import XCTest

@testable import RefineID

/// What the requester tells its user when its search ends: the code is
/// called not accepted only when every phone tried refused it, and a search
/// that tried none says no phone in pairing mode was found (RAPP v26.10.22
/// §4.2, "Trying Each Custodian in Pairing Mode" item 6).
internal final class RappPairingSearchMessageTests: XCTestCase {
  private typealias Reason = RappPairingSearch<PairingEndpoint>.CloseReason

  private static let notAccepted = String(localized: "The pairing code was not accepted")

  internal func testOnlyEveryRefusalIsAWrongCode() {
    XCTAssertEqual(RappPairingModel.failure(for: Reason.notAccepted), Self.notAccepted)
    let others: [Reason] = [
      .noneInPairingMode, .ceremonyEnded(.transportFailure), .ceremonyEnded(.protocolFailure),
    ]
    for reason in others {
      XCTAssertNotEqual(RappPairingModel.failure(for: reason), Self.notAccepted, "\(reason)")
    }
  }

  internal func testASearchThatTriedNoPhoneSaysNoneWasFound() {
    XCTAssertEqual(
      RappPairingModel.failure(for: Reason.noneInPairingMode),
      String(localized: "No phone in pairing mode was found"))
  }

  internal func testALocalCloseShowsNothing() {
    XCTAssertNil(RappPairingModel.failure(for: Reason.localRequest))
  }

  internal func testAFailureAfterTheCodeWasTakenEndsThePairing() {
    XCTAssertEqual(
      RappPairingModel.failure(for: Reason.ceremonyEnded(.attemptTimedOut)),
      String(localized: "Pairing ended before it was completed"))
  }

  internal func testNoneFoundIsSaidInEveryLanguage() throws {
    let catalog = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources/App/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
    let strings = try XCTUnwrap((json as? [String: Any])?["strings"] as? [String: Any])
    let entry = try XCTUnwrap(strings["No phone in pairing mode was found"] as? [String: Any])
    let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
    for (language, expected) in [
      ("fi", "Yhdistämistilassa olevaa puhelinta ei löytynyt"),
      ("sv", "Ingen telefon i parkopplingsläge hittades"),
    ] {
      let localization = try XCTUnwrap(localizations[language] as? [String: Any])
      let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
      XCTAssertEqual(unit["value"] as? String, expected, language)
    }
  }
}
