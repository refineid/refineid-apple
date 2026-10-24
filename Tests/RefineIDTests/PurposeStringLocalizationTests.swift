// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// Every purpose string the system shows in a permission prompt speaks the
/// holder's language: the string catalog carries a Finnish and a Swedish
/// translation under the Info.plist key the system looks up.
@Suite
internal struct PurposeStringLocalizationTests {
  /// The Info.plists the app builds with, on iPhone and iPad, and on the Mac.
  private static let builtPlists = [
    "Config/RefineID-iOS-Info.plist",
    "Config/RefineID-Store-Info.plist",
  ]

  /// The languages the app ships besides English.
  private static let translatedLanguages = ["fi", "sv"]

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// Whether `key` names a purpose string the system shows the holder.
  private static func isPurposeString(_ key: String) -> Bool {
    key.hasSuffix("UsageDescription")
  }

  private static func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appending(path: path))
    return try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }

  private static func catalog() throws -> [String: Any] {
    let data = try Data(contentsOf: root.appending(path: "Sources/App/InfoPlist.xcstrings"))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(json["strings"] as? [String: Any])
  }

  /// Gathers every dictionary key and string value in `value`, at any depth.
  private static func collect(_ value: Any, into carried: inout Set<String>) {
    switch value {
    case let dictionary as [String: Any]:
      for (key, nested) in dictionary {
        carried.insert(key)
        collect(nested, into: &carried)
      }

    case let array as [Any]:
      for nested in array {
        collect(nested, into: &carried)
      }

    case let text as String:
      carried.insert(text)

    default:
      break
    }
  }

  @Test("Each built purpose string has a Finnish and a Swedish translation under its key")
  internal func purposeStringsAreTranslated() throws {
    let strings = try Self.catalog()
    var keys = Set<String>()
    for path in Self.builtPlists {
      keys.formUnion(try Self.plist(path).keys.filter(Self.isPurposeString))
    }
    #expect(keys.contains("NSLocalNetworkUsageDescription"))
    for key in keys.sorted() {
      let entry = try #require(strings[key] as? [String: Any], "\(key) is not in the catalog")
      let localizations = try #require(entry["localizations"] as? [String: Any])
      for language in Self.translatedLanguages {
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        let value = unit?["value"] as? String ?? ""
        #expect(!value.isEmpty, "\(key) has no \(language) translation")
        #expect(unit?["state"] as? String == "translated", "\(key) \(language) is not translated")
      }
    }
  }

  /// The catalog compiles an English table too, and a key with no English
  /// unit there shows the holder the key itself in place of the text.
  @Test("Each built purpose string's English unit is the text its Info.plist carries")
  internal func purposeStringsCarryTheirEnglishText() throws {
    let strings = try Self.catalog()
    for path in Self.builtPlists {
      for (key, value) in try Self.plist(path) where Self.isPurposeString(key) {
        let entry = try #require(strings[key] as? [String: Any], "\(key) is not in the catalog")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        let unit = (localizations["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
        #expect(unit?["value"] as? String == value as? String, "\(key) English differs in \(path)")
      }
    }
  }

  @Test("The catalog holds no purpose string keyed by its English text")
  internal func noPurposeStringIsKeyedByItsText() throws {
    let strings = try Self.catalog()
    var texts = Set<String>()
    for path in Self.builtPlists {
      let plist = try Self.plist(path)
      for (key, value) in plist where Self.isPurposeString(key) {
        if let text = value as? String {
          texts.insert(text)
        }
      }
    }
    #expect(texts.isDisjoint(with: strings.keys))
  }

  @Test("Every hand-kept catalog entry names a key or a text a built Info.plist carries")
  internal func noCatalogEntryIsOrphaned() throws {
    let strings = try Self.catalog()
    var carried = Set<String>()
    for path in Self.builtPlists {
      Self.collect(try Self.plist(path), into: &carried)
    }
    for (key, value) in strings {
      let entry = try #require(value as? [String: Any])
      guard entry["extractionState"] as? String == "manual" else { continue }
      #expect(carried.contains(key), "\(key) is in the catalog but in no built Info.plist")
    }
  }
}
