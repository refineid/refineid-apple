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
}
