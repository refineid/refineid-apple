// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@testable import RefineIDTestHost

/// Document verification is "tarkastaa" in Finnish, and the trusted
/// lists are the EU's "luotetut luettelot" (Regulation (EU) No 910/2014
/// Article 22), in the tables the app ships.
@Suite
internal struct VerifyWordingTests {
  private static let finnish = "fi"
  private static let documentSigningTable = "DocumentSigning"
  private static let localizableTable = "Localizable"
  private static let compiledTableType = "strings"
  private static let verifyKeyPrefix = "verify."
  private static let authenticationStem = "todenn"
  private static let trustedListsTerm = "EU:n luotet"

  /// The keys of the main table that speak of verifying a document.
  private static let localizableVerifyKeys = [
    "Verify…",
    "Drop documents here to sign or verify them.",
    "Drop documents here to verify them.",
    "Documents to verify",
  ]

  /// The trusted-lists strings, each naming the EU's lists.
  private static let trustedListKeys = [
    "verify.trustedLists",
    "verify.refreshTrustedLists",
    "verify.errorNoTrustedLists",
    "verify.errorOfflineNoTrustedLists",
  ]

  /// The level strings.
  private static let levelKeys = [
    "verify.level",
    "verify.level.archivalUntil",
    "verify.level.archivalExpired",
    "verify.level.archivalUnknown",
    "verify.level.longTerm",
    "verify.level.timestamped",
    "verify.level.basic",
  ]

  /// An archive timestamp's validity end, and a moment before it.
  private static let validityEnd = Date(timeIntervalSince1970: 2_051_222_400)
  private static let beforeValidityEnd = Date(timeIntervalSince1970: 1_800_000_000)

  /// How the baseline profiles' codes begin.
  private static let profileCodePrefix = "B-"

  /// One compiled Finnish table of the app.
  private static func finnishTable(_ name: String) throws -> [String: String] {
    let path = try #require(
      Bundle.main.path(
        forResource: name, ofType: Self.compiledTableType, inDirectory: nil,
        forLocalization: Self.finnish))
    let data = try Data(contentsOf: URL(filePath: path))
    return try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
  }

  @Test
  internal func noFinnishVerifyStringSaysTodentaa() throws {
    let signing = try Self.finnishTable(Self.documentSigningTable)
    let main = try Self.finnishTable(Self.localizableTable)
    var verifyStrings = signing.filter { key, _ in key.hasPrefix(Self.verifyKeyPrefix) }
    try #require(!verifyStrings.isEmpty)
    for key in Self.localizableVerifyKeys {
      let value: String = try #require(main[key], "\(key) has no Finnish translation")
      verifyStrings[key] = value
    }
    for (key, value) in verifyStrings {
      #expect(!value.lowercased().contains(Self.authenticationStem), "\(key): \(value)")
    }
  }

  @Test
  internal func theTrustedListsAreTheEusLuotetutLuettelot() throws {
    let signing = try Self.finnishTable(Self.documentSigningTable)
    for key in Self.trustedListKeys {
      let value = try #require(signing[key], "\(key) has no Finnish translation")
      #expect(value.contains(Self.trustedListsTerm), "\(key): \(value)")
    }
  }

  /// The level a signature reached is said in words: the archival level
  /// carries the check, the others say what is missing, and no Finnish
  /// level text shows the profile's code.
  @Test
  internal func theLevelIsSaidInWordsAndArchivalHolds() throws {
    let levels: [SignatureLevel] = [.longTermArchival, .longTerm, .timestamped, .basic]
    for level in levels {
      let value = VerifySignatureSection.levelValue(
        level, validUntil: Self.validityEnd, now: Self.beforeValidityEnd)
      #expect(value.text?.isEmpty == false)
      let holds = value.indicator == .holds
      #expect(holds == (level == .longTermArchival), "\(level)")
    }
    let signing = try Self.finnishTable(Self.documentSigningTable)
    for key in Self.levelKeys {
      let value = try #require(signing[key], "\(key) has no Finnish translation")
      #expect(!value.contains(Self.profileCodePrefix), "\(key): \(value)")
    }
  }
}
