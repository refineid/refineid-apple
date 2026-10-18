// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The `mode=withdrawn` stream TXT record (RAPP v26.10.18 §4.5).
internal struct WithdrawnRecord: Equatable {
  internal static let entryCount = 8
  internal static let counterSeconds: UInt64 = 60

  private static let versionIndex = 0
  private static let modeIndex = 1
  private static let listIndex = 2
  private static let mode = "withdrawn"
  private static let entriesKey = "withdrawn"

  internal let entries: [Data]

  internal var textEntries: [(String, String)] {
    [
      (AnnouncementText.versionKey, AnnouncementText.version),
      (AnnouncementText.modeKey, Self.mode),
      (Self.entriesKey, AnnouncementText.encode(entries)),
    ]
  }

  internal static func counter(unixTimeSeconds: UInt64) -> UInt64 {
    unixTimeSeconds / counterSeconds
  }

  /// The hints of the 8 most recently used pairings and random fillers,
  /// in an order drawn at random.
  internal static func assemble(
    _ candidates: [AnnouncementCandidate], random: (Int) -> Data?
  ) -> Self? {
    let hints = AnnouncementText.mostRecentlyUsed(candidates, limit: entryCount)
    var keyed: [(order: Data, entry: Data)] = []
    for index in 0..<entryCount {
      guard let order = random(AnnouncementText.hintSize) else { return nil }
      let entry: Data
      if index < hints.count {
        entry = hints[index]
      } else {
        guard let filler = random(AnnouncementText.hintSize) else { return nil }
        entry = filler
      }
      keyed.append((order, entry))
    }
    keyed.sort { $0.order.lexicographicallyPrecedes($1.order) }
    return Self(entries: keyed.map(\.entry))
  }

  internal static func parse(_ entries: [(String, String)]) -> Self? {
    guard
      let values = try? AnnouncementText.values(
        entries, keys: [AnnouncementText.versionKey, AnnouncementText.modeKey, entriesKey]),
      values[Self.versionIndex] == AnnouncementText.version,
      values[Self.modeIndex] == mode,
      let list = values[Self.listIndex]
    else { return nil }
    let parsed = AnnouncementText.decode(list, maximum: entryCount)
    guard parsed.count == entryCount else { return nil }
    return Self(entries: parsed)
  }
}
