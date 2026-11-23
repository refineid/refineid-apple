// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The ATS justification App Review reads, pinned.
///
/// Apple requires a justification for `NSAllowsArbitraryLoads`, and App
/// Review reads the version's review notes, not a property list comment:
/// comments do not survive plist compilation. Both platform notes carry
/// the justification.
@Suite
internal struct AppStoreReviewNotesTests {
  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// App Store Connect's character limit for App Review notes.
  private static let reviewNoteLimit = 4_000

  /// The one fixed cleartext dependency both application plists name.
  private static let timestampAuthorityURL = "http://timestamp.sectigo.com/qualified"

  /// The rationale the notes must keep: what is fetched and from where.
  private static let justificationPhrases = [
    "NSAllowsArbitraryLoads",
    "OCSP",
    "CRL",
    "trusted lists",
    "revocation",
  ]

  /// The platform notes, keyed by platform.
  private static func reviewNotes() throws -> [String: Any] {
    let data = try Data(
      contentsOf: root.appending(path: "Metadata/appstore.json"))
    let metadata = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let review = try #require(metadata["review"] as? [String: Any])
    return try #require(review["notes"] as? [String: Any])
  }

  /// The notes of one platform name the ATS key, the fixed authority, and
  /// every source a signature fetches from.
  private static func expectJustification(for platform: String, named name: String) throws {
    let notes = try Self.reviewNotes()
    let text = try #require(notes[platform] as? String)
    #expect(
      text.contains(timestampAuthorityURL),
      "the \(name) notes lost the fixed authority")
    for phrase in justificationPhrases {
      #expect(text.contains(phrase), "the \(name) notes lost \(phrase)")
    }
  }

  /// The macOS notes justify the open ATS.
  @Test
  internal func macOSNotesJustifyTheOpenATS() throws {
    try Self.expectJustification(for: "macos", named: "macOS")
  }

  /// The iPhone notes justify the open ATS.
  @Test
  internal func iOSNotesJustifyTheOpenATS() throws {
    try Self.expectJustification(for: "ios", named: "iPhone")
  }

  /// Neither platform's notes exceed the field App Store Connect accepts.
  @Test
  internal func reviewNotesStayWithinTheFieldLimit() throws {
    let notes = try Self.reviewNotes()
    for platform in ["ios", "macos"] {
      let text = try #require(notes[platform] as? String)
      #expect(
        text.count <= Self.reviewNoteLimit,
        "\(platform) review notes exceed the App Store Connect field")
    }
  }
}
