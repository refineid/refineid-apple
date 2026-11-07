// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security
import XCTest

@testable import RefineIDTestHost

/// A write the system refused for lack of space says so, in the place the
/// failed operation already reports; every other failure keeps its words.
internal final class DiskFullMessageTests: XCTestCase {
  private typealias Reason = RappPairingSearch<PairingEndpoint>.CloseReason

  private static let diskFull = String(
    localized: "The disk is full. Free some space and try again.")

  /// The catalog key of the full-disk sentence.
  private static let diskFullKey = "The disk is full. Free some space and try again."

  /// A fallback no full disk produces.
  private static let otherwise = "not a full disk"

  internal func testAPairingStoredOutOfSpaceSaysTheDiskIsFull() {
    XCTAssertEqual(
      RappPairingModel.failure(for: Reason.ceremonyEnded(.outOfSpace))?.message, Self.diskFull)
    XCTAssertEqual(
      RappPairingModel.failure(for: Reason.ceremonyEnded(.protocolFailure))?.message,
      String(localized: "Pairing ended before it was completed."))
  }

  internal func testAPairingTheKeychainRefusedSaysItWasNotStoredWithTheCause() throws {
    let bare = String(localized: "The pairing could not be stored.")
    XCTAssertEqual(
      RappPairingModel.failure(for: Reason.ceremonyEnded(.persistenceFailure(status: nil)))?
        .message,
      bare)
    let cause = try XCTUnwrap(SecCopyErrorMessageString(errSecMissingEntitlement, nil) as String?)
    let message = try XCTUnwrap(
      RappPairingModel.failure(
        for: Reason.ceremonyEnded(.persistenceFailure(status: errSecMissingEntitlement)))?.message)
    XCTAssertEqual(message, String(localized: "The pairing could not be stored. \(cause)"))
    XCTAssertTrue(message.hasSuffix(cause))
  }

  internal func testThePairingNotStoredSentenceIsSaidInEveryLanguage() throws {
    let catalog = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources/App/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
    let strings = try XCTUnwrap((json as? [String: Any])?["strings"] as? [String: Any])
    let expected = [
      ("fi", "Yhdistämistä ei voitu tallentaa."),
      ("sv", "Parkopplingen kunde inte sparas."),
    ]
    for (key, suffix) in [
      ("The pairing could not be stored.", ""), ("The pairing could not be stored. %@", " %@"),
    ] {
      let entry = try XCTUnwrap(strings[key] as? [String: Any])
      let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
      for (language, value) in expected {
        let localization = try XCTUnwrap(localizations[language] as? [String: Any])
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        XCTAssertEqual(unit["value"] as? String, value + suffix, language)
      }
    }
  }

  internal func testACardAccessNumberRefusedForSpaceSaysTheDiskIsFull() {
    XCTAssertEqual(CardCredentialsModel.saveFailure(errSecDiskFull), Self.diskFull)
    XCTAssertNil(CardCredentialsModel.saveFailure(errSecIO))
    XCTAssertNil(CardCredentialsModel.saveFailure(errSecInteractionNotAllowed))
  }

  internal func testAVaultRefusedForSpaceSaysTheDiskIsFull() {
    XCTAssertEqual(
      DiskFullMessage.message(
        for: RappDeviceVault.Failure.unavailable(errSecDiskFull), otherwise: Self.otherwise),
      Self.diskFull)
    XCTAssertEqual(
      DiskFullMessage.message(
        for: RappDeviceVault.Failure.unavailable(errSecIO), otherwise: Self.otherwise),
      Self.otherwise)
  }

  internal func testASignedDocumentWrittenOutOfSpaceSaysTheDiskIsFull() {
    XCTAssertEqual(
      DocumentSigningMessage.message(for: CocoaError(.fileWriteOutOfSpace)), Self.diskFull)
    XCTAssertEqual(DocumentSigningMessage.message(for: POSIXError(.ENOSPC)), Self.diskFull)
    XCTAssertNotEqual(
      DocumentSigningMessage.message(for: CocoaError(.fileWriteNoPermission)), Self.diskFull)
  }

  internal func testTheDiskFullSentenceIsSaidInEveryLanguage() throws {
    let catalog = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources/App/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
    let strings = try XCTUnwrap((json as? [String: Any])?["strings"] as? [String: Any])
    let entry = try XCTUnwrap(strings[Self.diskFullKey] as? [String: Any])
    let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
    let expected = [
      ("fi", "Levy on täynnä. Vapauta tilaa ja yritä uudelleen."),
      ("sv", "Disken är full. Frigör utrymme och försök igen."),
    ]
    for (language, value) in expected {
      let localization = try XCTUnwrap(localizations[language] as? [String: Any])
      let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
      XCTAssertEqual(unit["value"] as? String, value, language)
    }
  }
}
