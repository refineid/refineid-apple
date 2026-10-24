// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

@testable import RefineID

/// The phone's PIN prompt names the act in its title and, in one sentence,
/// the computer that asks and the documents a signature covers.
internal final class RappAuthorizationPromptTests: XCTestCase {
  private static let computer = "Office computer"
  private static let document = "contract.pdf"
  private static let secondDocument = "appendix.pdf"

  internal func testAuthenticationNamesTheComputer() {
    XCTAssertEqual(
      RappAuthorizationPrompt.authenticationTitle, String(localized: "Authentication"))
    XCTAssertEqual(
      RappAuthorizationPrompt.authenticationMessage(computer: Self.computer),
      String(localized: "\(Self.computer) asks you to authenticate."))
  }

  internal func testSignatureNamesTheComputerAndTheDocument() {
    XCTAssertEqual(RappAuthorizationPrompt.signatureTitle, String(localized: "Signature"))
    XCTAssertEqual(
      RappAuthorizationPrompt.signatureMessage(computer: Self.computer, documents: [Self.document]),
      String(localized: "\(Self.computer) asks you to sign \(Self.document)."))
  }

  internal func testABatchNamesEveryDocumentInOrder() throws {
    let message = RappAuthorizationPrompt.signatureMessage(
      computer: Self.computer, documents: [Self.document, Self.secondDocument])
    let named = ListFormatter.localizedString(byJoining: [Self.document, Self.secondDocument])
    XCTAssertEqual(
      message, String(localized: "\(Self.computer) asks you to sign the documents \(named)."))
    let first = try XCTUnwrap(message.range(of: Self.document))
    let second = try XCTUnwrap(message.range(of: Self.secondDocument))
    XCTAssertLessThan(first.lowerBound, second.lowerBound)
  }

  internal func testASignatureWithoutADocumentNamesOnlyTheComputer() {
    XCTAssertEqual(
      RappAuthorizationPrompt.signatureMessage(computer: Self.computer, documents: []),
      String(localized: "\(Self.computer) asks you to sign."))
  }

  internal func testEveryPromptStringIsTranslated() throws {
    let catalog = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Sources/App/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
    let strings = try XCTUnwrap((json as? [String: Any])?["strings"] as? [String: Any])
    let expected: [String: [String: String]] = [
      "Authentication": ["fi": "Tunnistautuminen", "sv": "Autentisering"],
      "%@ asks you to authenticate.": [
        "fi": "%@ pyytää tunnistautumaan.", "sv": "%@ ber dig att autentisera dig.",
      ],
      "Signature": ["fi": "Allekirjoitus", "sv": "Underskrift"],
      "%@ asks you to sign %@.": [
        "fi": "%1$@ pyytää allekirjoittamaan asiakirjan %2$@.",
        "sv": "%1$@ ber dig att underteckna %2$@.",
      ],
      "%@ asks you to sign the documents %@.": [
        "fi": "%1$@ pyytää allekirjoittamaan asiakirjat %2$@.",
        "sv": "%1$@ ber dig att underteckna dokumenten %2$@.",
      ],
      "%@ asks you to sign.": [
        "fi": "%@ pyytää allekirjoittamaan.", "sv": "%@ ber dig att underteckna.",
      ],
    ]
    for (key, translations) in expected {
      let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
      let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
      for (language, value) in translations {
        let localization = try XCTUnwrap(localizations[language] as? [String: Any], key)
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], key)
        XCTAssertEqual(unit["value"] as? String, value, "\(key) \(language)")
      }
    }
  }
}
