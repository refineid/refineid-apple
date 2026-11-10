// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The Settings words are said in every language.
  @Suite
  internal struct SettingsStringsTests {
    private static var catalog: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/App/Localizable.xcstrings")
    }

    /// Each Settings key carries its Finnish and Swedish words.
    @Test
    internal func settingsKeysAreTranslated() throws {
      let data = try Data(contentsOf: Self.catalog)
      let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
      )
      let strings = try #require(json["strings"] as? [String: Any])
      let expected = [
        ("Time Stamp", "Aikaleima", "Tidsstämpel"),
        ("Address", "Osoite", "Adress"),
        ("Restore Defaults", "Palauta oletukset", "Återställ standardvärden"),
        ("Not a usable address", "Osoite ei ole käyttökelpoinen", "Adressen kan inte användas"),
        (
          "Signing Service", "Allekirjoituspalvelu",
          "Signeringstjänst"
        ),
        (
          "Signature Creation Service",
          "Allekirjoituspalvelu (Signature Creation Service)",
          "Signeringstjänst (Signature Creation Service)"
        ),
      ]
      for (key, finnish, swedish) in expected {
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        for (language, value) in [("fi", finnish), ("sv", swedish)] {
          let localization = try #require(localizations[language] as? [String: Any])
          let unit = try #require(localization["stringUnit"] as? [String: Any])
          #expect(unit["value"] as? String == value, "\(key) in \(language)")
        }
      }
    }

    /// The iOS Settings bundle edits the store's key, prefilled with
    /// the store's default.
    @Test
    internal func settingsBundleEditsTheStore() throws {
      let bundle = Self.catalog
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Settings.bundle/Root.plist")
      let data = try Data(contentsOf: bundle)
      let plist = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
      )
      let specifiers = try #require(plist["PreferenceSpecifiers"] as? [[String: Any]])
      let fields = specifiers.filter { $0["Type"] as? String == "PSTextFieldSpecifier" }
      let field = try #require(fields.first)
      #expect(fields.count == 1)
      #expect(field["Key"] as? String == TimestampAuthorityStore.key)
      #expect(field["DefaultValue"] as? String == TimestampAuthorityStore.defaultAuthority)
    }
  }

#endif
