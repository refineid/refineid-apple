// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The ATS justification App Review reads, pinned.
///
/// Apple requires a justification for `NSAllowsArbitraryLoads`, and App
/// Review reads the version's review notes, not a property list comment:
/// comments do not survive plist compilation. The macOS notes carry the
/// MVP's justification.
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

  /// The macOS notes name the ATS key, the fixed authority, and every
  /// source an archival signature fetches from.
  @Test
  internal func macOSNotesJustifyTheOpenATS() throws {
    let notes = try Self.reviewNotes()
    let macOS = try #require(notes["macos"] as? String)
    #expect(macOS.contains(Self.timestampAuthorityURL))
    for phrase in Self.justificationPhrases {
      #expect(macOS.contains(phrase), "the macOS notes lost \(phrase)")
    }
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
