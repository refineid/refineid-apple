// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The phone's PIN prompt names the act in its title and, in one sentence,
  /// the computer that asks and the documents a signature covers.
  @Suite(.serialized)
  internal final class RappAuthorizationPromptTests {
    private static let computer = "Office computer"
    private static let document = "contract.pdf"
    private static let secondDocument = "appendix.pdf"

    @Test
    internal func testAuthenticationNamesTheComputer() {
      #expect(
        (RappAuthorizationPrompt.authenticationTitle) == (String(localized: "Authentication")))
      #expect(
        (RappAuthorizationPrompt.authenticationMessage(computer: Self.computer))
          == (String(localized: "\(Self.computer) asks you to authenticate.")))
    }

    @Test
    internal func testSignatureNamesTheComputerAndTheDocument() {
      #expect((RappAuthorizationPrompt.signatureTitle) == (String(localized: "Signature")))
      #expect(
        (RappAuthorizationPrompt.signatureMessage(
          computer: Self.computer, documents: [Self.document]))
          == (String(localized: "\(Self.computer) asks you to sign \(Self.document).")))
    }

    @Test
    internal func testABatchNamesEveryDocumentInOrder() throws {
      let message = RappAuthorizationPrompt.signatureMessage(
        computer: Self.computer, documents: [Self.document, Self.secondDocument])
      let named = ListFormatter.localizedString(byJoining: [Self.document, Self.secondDocument])
      #expect(
        (message)
          == (String(localized: "\(Self.computer) asks you to sign the documents \(named).")))
      let first = try #require(message.range(of: Self.document))
      let second = try #require(message.range(of: Self.secondDocument))
      #expect((first.lowerBound) < (second.lowerBound))
    }

    @Test
    internal func testASignatureWithoutADocumentNamesOnlyTheComputer() {
      #expect(
        (RappAuthorizationPrompt.signatureMessage(computer: Self.computer, documents: []))
          == (String(localized: "\(Self.computer) asks you to sign.")))
    }

    @Test
    internal func testEveryPromptStringIsTranslated() throws {
      let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/App/Localizable.xcstrings")
      let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
      let strings = try #require((json as? [String: Any])?["strings"] as? [String: Any])
      let expected: [String: [String: String]] = [
        "Authentication": ["fi": "Tunnistautuminen", "sv": "Identifiering"],
        "%@ asks you to authenticate.": [
          "fi": "%@ pyytää tunnistautumaan.", "sv": "%@ ber dig att identifiera dig.",
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
        let entry = try #require(strings[key] as? [String: Any], key)
        let localizations = try #require(entry["localizations"] as? [String: Any], key)
        for (language, value) in translations {
          let localization = try #require(localizations[language] as? [String: Any], key)
          let unit = try #require(localization["stringUnit"] as? [String: Any], key)
          #expect((unit["value"] as? String) == (value), "\(key) \(language)")
        }
      }
    }
  }
#endif
