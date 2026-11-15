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

    /// One key's expected Finnish and Swedish words.
    private struct TranslationRow {
      let key: String
      let finnish: String
      let swedish: String
    }

    private static var catalog: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/App/Localizable.xcstrings")
    }

    /// Each expected key carries its Finnish and Swedish words.
    private static func check(
      _ expected: [TranslationRow],
      in strings: [String: Any]
    ) throws {
      for row in expected {
        let entry = try #require(strings[row.key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        for (language, value) in [("fi", row.finnish), ("sv", row.swedish)] {
          let localization = try #require(localizations[language] as? [String: Any])
          let unit = try #require(localization["stringUnit"] as? [String: Any])
          #expect(unit["value"] as? String == value, "\(row.key) in \(language)")
        }
      }
    }

    private static func catalogStrings() throws -> [String: Any] {
      let data = try Data(contentsOf: Self.catalog)
      let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
      )
      return try #require(json["strings"] as? [String: Any])
    }

    /// Each Settings key carries its Finnish and Swedish words.
    @Test
    internal func settingsKeysAreTranslated() throws {
      try Self.check(
        [
          TranslationRow(key: "Time Stamp", finnish: "Aikaleima", swedish: "Tidsstämpel"),
          TranslationRow(
            key: "Qualified timestamp server",
            finnish: "Hyväksytty aikaleimapalvelin",
            swedish: "Kvalificerad tidsstämpelserver"
          ),
          TranslationRow(
            key: "Restore Defaults",
            finnish: "Palauta oletukset",
            swedish: "Återställ standardvärden"
          ),
          TranslationRow(
            key: "Not a usable address",
            finnish: "Osoite ei ole käyttökelpoinen",
            swedish: "Adressen kan inte användas"
          ),
          TranslationRow(
            key: "Signing Service",
            finnish: "Allekirjoituspalvelu",
            swedish: "Signeringstjänst"
          ),
          TranslationRow(
            key: "Signature Creation Service",
            finnish: "Allekirjoituspalvelu (Signature Creation Service)",
            swedish: "Signeringstjänst (Signature Creation Service)"
          ),
        ],
        in: try Self.catalogStrings()
      )
    }

    /// Each timestamp Test key carries its Finnish and Swedish words.
    @Test
    internal func timestampStatusKeysAreTranslated() throws {
      try Self.check(
        [
          TranslationRow(key: "Not tested", finnish: "Ei testattu", swedish: "Ej testad"),
          TranslationRow(key: "Testing…", finnish: "Testataan…", swedish: "Testar…"),
          TranslationRow(
            key: "Verified %@",
            finnish: "Vahvistettu %1$@",
            swedish: "Verifierad %1$@"
          ),
          TranslationRow(
            key: "Failed %@",
            finnish: "Epäonnistui %1$@",
            swedish: "Misslyckades %1$@"
          ),
          TranslationRow(
            key: "Failed %@: %@",
            finnish: "Epäonnistui %1$@: %2$@",
            swedish: "Misslyckades %1$@: %2$@"
          ),
        ],
        in: try Self.catalogStrings()
      )
    }

    /// Each timestamp failure reason carries its Finnish and Swedish words.
    @Test
    internal func timestampReasonKeysAreTranslated() throws {
      try Self.check(
        [
          TranslationRow(
            key: "Not on the EU trusted lists",
            finnish: "Ei EU:n luottamuslistoilla",
            swedish: "Inte på EU:s förteckning över betrodda tjänster"
          ),
          TranslationRow(
            key: "EU trusted lists unavailable",
            finnish: "EU:n luottamuslistat eivät olleet saatavilla",
            swedish: "EU:s förteckningar över betrodda tjänster var inte tillgängliga"
          ),
          TranslationRow(
            key: "Invalid timestamp response",
            finnish: "Virheellinen aikaleimavastaus",
            swedish: "Ogiltigt tidsstämpelsvar"
          ),
          TranslationRow(
            key: "Secure random bytes unavailable",
            finnish: "Suojattuja satunnaislukuja ei saatu",
            swedish: "Säkra slumptal kunde inte skapas"
          ),
          TranslationRow(
            key: "Timestamp declined",
            finnish: "Aikaleima evätty",
            swedish: "Tidsstämpel nekad"
          ),
          TranslationRow(
            key: "Service unreachable",
            finnish: "Palvelimeen ei saatu yhteyttä",
            swedish: "Tjänsten kunde inte nås"
          ),
          TranslationRow(
            key: "No network connection",
            finnish: "Ei verkkoyhteyttä",
            swedish: "Ingen nätverksanslutning"
          ),
          TranslationRow(
            key: "Check the address and test again.",
            finnish: "Tarkista osoite ja testaa uudelleen.",
            swedish: "Kontrollera adressen och testa igen."
          ),
        ],
        in: try Self.catalogStrings()
      )
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
