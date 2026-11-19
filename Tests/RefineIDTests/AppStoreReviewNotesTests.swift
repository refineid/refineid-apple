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
  private static let timestampAuthorityHost = "timestamp.sectigo.com"

  /// The macOS notes name the ATS key, its cause, and the fixed authority,
  /// and neither platform's notes exceed the field.
  @Test
  internal func macOSNotesJustifyTheOpenATS() throws {
    let data = try Data(
      contentsOf: Self.root.appending(path: "Metadata/appstore.json"))
    let metadata = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let review = try #require(metadata["review"] as? [String: Any])
    let notes = try #require(review["notes"] as? [String: Any])
    let macOS = try #require(notes["macos"] as? String)
    #expect(macOS.contains("NSAllowsArbitraryLoads"))
    #expect(macOS.contains(Self.timestampAuthorityHost))
    #expect(macOS.contains("revocation"))
    for platform in ["ios", "macos"] {
      let text = try #require(notes[platform] as? String)
      #expect(
        text.count <= Self.reviewNoteLimit,
        "\(platform) review notes exceed the App Store Connect field")
    }
  }
}
