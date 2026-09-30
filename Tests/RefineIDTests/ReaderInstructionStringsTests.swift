// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The no-card instructions say the same thing in every language:
/// connect a reader when none is attached, insert the identity card
/// when one is.
@Suite
internal struct ReaderInstructionStringsTests {
  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func catalog() throws -> [String: Any] {
    let url = root.appending(path: "Sources/App/Localizable.xcstrings")
    let data = try Data(contentsOf: url)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["sourceLanguage"] as? String == "en")
    return try #require(json["strings"] as? [String: Any])
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

  @Test
  internal func noReaderInstructionMatchesInEveryLanguage() throws {
    let strings = try Self.catalog()
    #expect(
      try Self.value(for: "Connect a card reader", language: "fi", in: strings)
        == "Kytke kortinlukija"
    )
    #expect(
      try Self.value(for: "Connect a card reader", language: "sv", in: strings)
        == "Anslut en kortläsare"
    )
  }

  @Test
  internal func readerWithoutCardInstructionMatchesInEveryLanguage() throws {
    let strings = try Self.catalog()
    #expect(
      try Self.value(
        for: "Insert your identity card into the reader", language: "fi", in: strings
      ) == "Laita henkilökortti lukijaan"
    )
    #expect(
      try Self.value(
        for: "Insert your identity card into the reader", language: "sv", in: strings
      ) == "Sätt in identitetskortet i läsaren"
    )
  }

  @Test
  internal func settingsInstructionMatchesInEveryLanguage() throws {
    let strings = try Self.catalog()
    #expect(
      try Self.value(
        for: "Connect a card reader and insert your card.", language: "fi", in: strings
      ) == "Kytke kortinlukija ja laita henkilökortti siihen."
    )
    #expect(
      try Self.value(
        for: "Connect a card reader and insert your card.", language: "sv", in: strings
      ) == "Anslut en kortläsare och sätt in identitetskortet i den."
    )
  }

  @Test
  internal func viewsUseTheTranslatedKeys() throws {
    let identity = try String(
      contentsOf: Self.root.appending(path: "Sources/App/IdentityStateView.swift"),
      encoding: .utf8
    )
    #expect(identity.contains("Insert your identity card into the reader"))
    #expect(identity.contains("Connect a card reader"))
    let prompt = try String(
      contentsOf: Self.root.appending(path: "Sources/App/RemotePairingPromptView.swift"),
      encoding: .utf8
    )
    #expect(prompt.contains("Insert your identity card into the reader"))
    let settings = try String(
      contentsOf: Self.root.appending(path: "Sources/App/RefineIDSettingsView.swift"),
      encoding: .utf8
    )
    #expect(settings.contains("Connect a card reader and insert your card."))
  }
}
