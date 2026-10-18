// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The `mode=session` stream TXT record, the discovery hints in it, and
/// the revocation announcement it may carry (RAPP v26.10.18 §4.6).
internal struct DiscoveryRecord: Equatable {
  internal static let maximumHints = 4
  internal static let epochSeconds: UInt64 = 900

  private static let versionIndex = 0
  private static let modeIndex = 1
  private static let listIndex = 2
  private static let revokedIndex = 3
  private static let mode = "session"
  private static let hintsKey = "hints"
  private static let revokedKey = "revoked"

  internal let hints: [Data]
  /// The revocation announcement's eight entries, when the record carries
  /// one.
  internal let revoked: RevokedAnnouncement?

  internal var textEntries: [(String, String)] {
    var entries = [
      (AnnouncementText.versionKey, AnnouncementText.version),
      (AnnouncementText.modeKey, Self.mode),
    ]
    if !hints.isEmpty {
      entries.append((Self.hintsKey, AnnouncementText.encode(hints)))
    }
    if let revoked {
      entries.append((Self.revokedKey, AnnouncementText.encode(revoked.entries)))
    }
    return entries
  }

  internal static func epoch(unixTimeSeconds: UInt64) -> UInt64 {
    unixTimeSeconds / epochSeconds
  }

  internal static func assemble(
    _ candidates: [AnnouncementCandidate], revoked: RevokedAnnouncement?
  ) -> Self {
    Self(
      hints: AnnouncementText.mostRecentlyUsed(candidates, limit: maximumHints),
      revoked: revoked)
  }

  /// The record `entries` encode, or `nil` when they are malformed: a key
  /// other than `v`, `mode`, `hints` and `revoked`, a repeated key, a
  /// `hints` list that is empty or too long, or a `revoked` value that is
  /// not exactly eight entries.
  internal static func parse(_ entries: [(String, String)]) -> Self? {
    guard
      let values = try? AnnouncementText.values(
        entries,
        keys: [AnnouncementText.versionKey, AnnouncementText.modeKey, hintsKey, revokedKey]),
      values[Self.versionIndex] == AnnouncementText.version,
      values[Self.modeIndex] == mode
    else { return nil }
    var parsedHints: [Data] = []
    if let list = values[Self.listIndex] {
      parsedHints = AnnouncementText.decode(list, maximum: maximumHints)
      guard !parsedHints.isEmpty else { return nil }
    }
    var parsedRevoked: RevokedAnnouncement?
    if let list = values[Self.revokedIndex] {
      guard let announcement = RevokedAnnouncement.parse(list) else { return nil }
      parsedRevoked = announcement
    }
    return Self(hints: parsedHints, revoked: parsedRevoked)
  }
}
