// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import XCTest

@testable import RefineIDTestHost

/// What card management tells the holder after an operation: each result
/// and failure is a localized sentence, and a composed message is one
/// translated format around a translated reason.
@MainActor
internal final class CardManagementOutcomeMessageTests: XCTestCase {
  private static func model() -> CardManagementModel {
    CardManagementModel(
      transport: .reader,
      activationRequired: false,
      cardAccessNumber: nil,
      activation: nil,
      activationNeeds: nil,
      pinLengths: nil
    )
  }

  private static func assertTranslations(of key: String, finnish: String, swedish: String) throws {
    let catalog = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources/App/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
    let strings = try XCTUnwrap((json as? [String: Any])?["strings"] as? [String: Any])
    let entry = try XCTUnwrap(strings[key] as? [String: Any])
    let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
    for (language, expected) in [("fi", finnish), ("sv", swedish)] {
      let localization = try XCTUnwrap(localizations[language] as? [String: Any])
      let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
      XCTAssertEqual(unit["value"] as? String, expected, language)
    }
  }

  internal func testAnActivationThatSetBothPinsSaysSo() {
    let model = Self.model()
    let report = CardMaintenance.ActivationReport(
      scheme: .activationCodeIsPuk, pin1: .success, pin2: .success)
    XCTAssertTrue(model.describe(report))
    XCTAssertEqual(
      model.notice, String(localized: "Card activated: PIN 1 and PIN 2 are set."))
    XCTAssertNil(model.failure)
  }

  internal func testAPartialActivationWrapsTheReason() throws {
    let model = Self.model()
    let remaining = try XCTUnwrap(RetryCount(attemptsRemaining: 4))
    let report = CardMaintenance.ActivationReport(
      scheme: .presetActivationPin, pin1: .success, pin2: .rejected(remaining: remaining))
    XCTAssertFalse(model.describe(report))
    let reason = CredentialOutcomeMessage.rejection(.activationPin, remaining: remaining)
    XCTAssertEqual(
      model.failure, String(localized: "PIN 1 was set, but PIN 2 was not: \(reason)"))
  }

  internal func testAnUnreadableCounterNamesTheEntry() {
    let message = Self.model().message(
      for: .floorRefused(.refuseUnreadable), presenting: .activationCode, spending: .puk)
    let name = String(localized: "activation PIN")
    XCTAssertEqual(
      message,
      String(localized: "The \(name) retry counter could not be read; nothing was sent."))
  }

  internal func testActivationSuccessIsSaidInEveryLanguage() throws {
    try Self.assertTranslations(
      of: "Card activated: PIN 1 and PIN 2 are set.",
      finnish: "Kortti aktivoitu: PIN 1 ja PIN 2 on asetettu.",
      swedish: "Kortet aktiverat: PIN 1 och PIN 2 har angetts.")
  }

  internal func testActivationEntryNamesAreSaidInEveryLanguage() throws {
    try Self.assertTranslations(
      of: "activation PIN", finnish: "aktivointitunnusluku", swedish: "aktiveringskod")
  }
}
