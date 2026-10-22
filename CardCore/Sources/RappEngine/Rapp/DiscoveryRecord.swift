// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The `mode=session` stream TXT record and the discovery hints in it
/// (RAPP transport and discovery hierarchy §4.3).
internal struct DiscoveryRecord: Equatable {
  internal static let maximumHints = 4
  internal static let epochSeconds: UInt64 = 900

  private static let versionIndex = 0
  private static let modeIndex = 1
  private static let listIndex = 2
  private static let mode = "session"
  private static let hintsKey = "hints"

  internal let hints: [Data]

  internal var textEntries: [(String, String)] {
    var entries = [
      (AnnouncementText.versionKey, AnnouncementText.version),
      (AnnouncementText.modeKey, Self.mode),
    ]
    if !hints.isEmpty {
      entries.append((Self.hintsKey, AnnouncementText.encode(hints)))
    }
    return entries
  }

  internal static func epoch(unixTimeSeconds: UInt64) -> UInt64 {
    unixTimeSeconds / epochSeconds
  }

  internal static func assemble(_ candidates: [AnnouncementCandidate]) -> Self {
    Self(hints: AnnouncementText.mostRecentlyUsed(candidates, limit: maximumHints))
  }

  /// The record `entries` encode, or `nil` when they are malformed: a key
  /// other than `v`, `mode` and `hints`, a repeated key, or a `hints` list
  /// that is empty or too long.
  internal static func parse(_ entries: [(String, String)]) -> Self? {
    guard
      let values = try? AnnouncementText.values(
        entries, keys: [AnnouncementText.versionKey, AnnouncementText.modeKey, hintsKey]),
      values[Self.versionIndex] == AnnouncementText.version,
      values[Self.modeIndex] == mode
    else { return nil }
    var parsedHints: [Data] = []
    if let list = values[Self.listIndex] {
      parsedHints = AnnouncementText.decode(list, maximum: maximumHints)
      guard !parsedHints.isEmpty else { return nil }
    }
    return Self(hints: parsedHints)
  }
}
