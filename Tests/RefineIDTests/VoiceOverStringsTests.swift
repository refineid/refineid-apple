// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// Every string VoiceOver can speak ships in all three languages.
///
/// VoiceOver reads the localized string: a key with no Finnish or
/// Swedish value shows a Finnish or Swedish holder English, or the key
/// itself. The completeness check below fails on any such key, and the
/// pins that follow name the exact words the macOS MVP window speaks
/// for its actions and its signing progress, so a rewording updates the
/// test that names it. The identity row's own words are pinned in
/// `ReaderInstructionStringsTests`.
@Suite
internal struct VoiceOverStringsTests {
  /// The string catalogs VoiceOver reads from.
  private static let catalogs = [
    "Sources/App/Localizable.xcstrings",
    "Sources/App/DocumentSigning.xcstrings",
    "Sources/App/VirtualIDCard.xcstrings",
    "Sources/App/InfoPlist.xcstrings",
    "Sources/TokenExtension/Localizable.xcstrings",
  ]

  /// The languages the app ships besides English.
  private static let translatedLanguages = ["fi", "sv"]

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func catalog(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appending(path: path))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["sourceLanguage"] as? String == "en", "\(path)")
    let strings = try #require(json["strings"] as? [String: Any])
    #expect(!strings.isEmpty, "\(path)")
    return strings
  }

  private static func value(
    for key: String, language: String, in strings: [String: Any]
  ) throws -> String {
    let entry = try #require(strings[key] as? [String: Any])
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let localization = try #require(localizations[language] as? [String: Any])
    let unit = try #require(localization["stringUnit"] as? [String: Any])
    return try #require(unit["value"] as? String)
  }

  /// Whether a localization speaks: a plain value, or every plural leaf.
  private static func isComplete(_ localization: [String: Any]) -> Bool {
    if let unit = localization["stringUnit"] as? [String: Any],
      let value = unit["value"] as? String, !value.isEmpty
    {
      return true
    }
    guard let variations = localization["variations"] as? [String: Any] else {
      return false
    }
    return leavesComplete(variations)
  }

  private static func leavesComplete(_ node: Any) -> Bool {
    guard let dict = node as? [String: Any], !dict.isEmpty else {
      return false
    }
    if let unit = dict["stringUnit"] as? [String: Any] {
      return (unit["value"] as? String)?.isEmpty == false
    }
    return dict.values.allSatisfy(leavesComplete)
  }

  /// Every spoken string inside a localization entry, including plural leaves.
  private static func spokenStrings(in node: Any) -> [String] {
    guard let dict = node as? [String: Any] else {
      return []
    }
    if let unit = dict["stringUnit"] as? [String: Any],
      let value = unit["value"] as? String
    {
      return [value]
    }
    return dict.keys.sorted().flatMap { key in
      spokenStrings(in: dict[key] as Any)
    }
  }

  @Test("Every catalog key speaks Finnish and Swedish")
  internal func everyKeySpeaksFinnishAndSwedish() throws {
    for path in Self.catalogs {
      let strings = try Self.catalog(at: path)
      for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
        let localizations = try #require(
          (entry as? [String: Any])?["localizations"] as? [String: Any],
          "\(path) \(key)")
        for language in Self.translatedLanguages {
          let localization = try #require(
            localizations[language] as? [String: Any],
            "\(path) \(key) has no \(language)")
          #expect(
            Self.isComplete(localization),
            "\(path) \(key) has no spoken \(language) text")
        }
      }
    }
  }

  @Test("The MVP window's actions match in every language")
  internal func mvpWindowActionsMatchInEveryLanguage() throws {
    let strings = try Self.catalog(at: "Sources/App/Localizable.xcstrings")
    let words: [String: [String: String]] = [
      "Drop documents here to sign them.": [
        "fi": "Pudota asiakirjat tähän allekirjoitettavaksi.",
        "sv": "Släpp dokument här för att underteckna dem.",
      ],
      "Sign…": ["fi": "Allekirjoita…", "sv": "Underteckna…"],
      "PIN Codes": ["fi": "PIN-koodit", "sv": "PIN-koder"],
      "A PIN code needs a reset": [
        "fi": "PIN-koodi on palautettava",
        "sv": "En PIN-kod måste återställas",
      ],
      "Connect a card reader.": [
        "fi": "Liitä kortinlukija.",
        "sv": "Anslut en kortläsare.",
      ],
    ]
    for (key, translations) in words {
      for (language, text) in translations {
        #expect(
          try Self.value(for: key, language: language, in: strings) == text,
          "\(key) \(language)")
      }
    }
  }

  @Test("The MVP window's signing progress matches in every language")
  internal func mvpSigningProgressMatchesInEveryLanguage() throws {
    let strings = try Self.catalog(at: "Sources/App/Localizable.xcstrings")
    let words: [String: [String: String]] = [
      "Signing document…": [
        "fi": "Allekirjoitetaan asiakirjaa…",
        "sv": "Undertecknar dokumentet…",
      ],
      "Reading the card…": ["fi": "Luetaan korttia…", "sv": "Läser kortet…"],
      "The signed document cannot replace the original.": [
        "fi": "Allekirjoitettu asiakirja ei voi korvata alkuperäistä.",
        "sv": "Det undertecknade dokumentet kan inte ersätta originalet.",
      ],
    ]
    for (key, translations) in words {
      for (language, text) in translations {
        #expect(
          try Self.value(for: key, language: language, in: strings) == text,
          "\(key) \(language)")
      }
    }
  }

  @Test("Document verification strings match in every language")
  internal func documentVerificationStringsMatchInEveryLanguage() throws {
    let strings = try Self.catalog(at: "Sources/App/Localizable.xcstrings")
    let words: [String: [String: String]] = [
      "Verify…": ["fi": "Tarkasta…", "sv": "Granska…"],
      "Documents to verify": [
        "fi": "Tarkastettavat asiakirjat",
        "sv": "Dokument att granska",
      ],
      "Drop documents here to sign or verify them.": [
        "fi": "Pudota asiakirjat tähän allekirjoitettavaksi tai tarkastettavaksi.",
        "sv": "Släpp dokument här för att underteckna eller granska dem.",
      ],
      "Drop documents here to verify them.": [
        "fi": "Pudota asiakirjat tähän tarkastettavaksi.",
        "sv": "Släpp dokument här för att granska dem.",
      ],
    ]
    for (key, translations) in words {
      for (language, text) in translations {
        #expect(
          try Self.value(for: key, language: language, in: strings) == text,
          "\(key) \(language)")
      }
    }
  }

  /// Finland-Swedish legal and administrative text uses the `underteckna` /
  /// `underskrift` family (Finlex, EU Regulation 910/2014 Swedish text, Kotus
  /// Sprakbruk) rather than the `signera` / `signering` stem.
  @Test("Every Swedish catalog string uses underteckna/underskrift terminology")
  internal func swedishCatalogStringsAvoidSigneraStem() throws {
    for path in Self.catalogs {
      let strings = try Self.catalog(at: path)
      for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
        let localizations = try #require(
          (entry as? [String: Any])?["localizations"] as? [String: Any],
          "\(path) \(key)")
        let swedish = try #require(
          localizations["sv"] as? [String: Any],
          "\(path) \(key) has no sv")
        let values = Self.spokenStrings(in: swedish)
        #expect(!values.isEmpty, "\(path) \(key) sv")
        for text in values {
          #expect(
            text.range(of: "signer", options: .caseInsensitive) == nil,
            "\(path) \(key) sv uses signer- stem: \(text)")
        }
      }
    }
  }
}
