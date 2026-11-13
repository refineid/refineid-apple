// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// The Settings words are said in every language.
  @Suite
  internal struct SettingsStringsTests {
    /// One language's expected Settings titles.
    private struct TitleRow {
      let language: String
      let authority: String
      let card: String
      let organization: String
    }

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

    /// Each Settings language carries the group titles.
    ///
    /// The address field carries no title: the URL takes the whole row.
    @Test
    internal func settingsBundleTitlesAreTranslated() throws {
      let bundle = Self.catalog
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Settings.bundle")
      for row in [
        TitleRow(
          language: "en",
          authority: "Qualified Time Stamping Authority",
          card: "Card",
          organization: "Organization Card"
        ),
        TitleRow(
          language: "fi",
          authority: "Hyväksytty aikaleimavarmentaja",
          card: "Kortti",
          organization: "Organisaatiokortti"
        ),
        TitleRow(
          language: "sv",
          authority: "Kvalificerad tidsstämplingsauktoritet",
          card: "Kort",
          organization: "Organisationskort"
        ),
      ] {
        let strings = bundle.appending(path: "\(row.language).lproj/Root.strings")
        let data = try Data(contentsOf: strings)
        let table = try #require(
          PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
        #expect(table["Qualified Time Stamping Authority"] == row.authority)
        #expect(table["Card"] == row.card)
        #expect(table["Organization Card"] == row.organization)
        #expect(table["Address"] == nil)
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
      #expect(field["DefaultValue"] as? String == TimestampAuthorityStore.defaultAddress)
      let organizationToggles = specifiers.filter { specifier in
        specifier["Key"] as? String == OrganizationCardStore.key
      }
      #if FEATURE_ORGANIZATION_CARD
        #expect(organizationToggles.count == 1)
      #else
        // No build enables organization cards right now, so Settings
        // offers no switch for them; a value stored earlier stays
        // stored and gated, not deleted.
        #expect(organizationToggles.isEmpty)
      #endif
    }
  }

#endif
