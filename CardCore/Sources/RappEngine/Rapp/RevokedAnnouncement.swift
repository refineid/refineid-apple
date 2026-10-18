// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `revoked` attribute of a `mode=session` record (RAPP v26.10.18
/// §4.6 item 4): the revocation hints of the up to eight most recently
/// revoked pairings, the rest random fillers, all in random order.
internal struct RevokedAnnouncement: Equatable {
  internal static let entryCount = 8

  internal let entries: [Data]

  private init(entries: [Data]) {
    self.entries = entries
  }

  /// Exactly eight entries drawn from `candidates`, whose last-used time
  /// is the revocation time, with random fillers in an order drawn at
  /// random; `nil` when the random source fails.
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

  /// The announcement `list` encodes, or `nil` unless it is exactly eight
  /// lowercase 16-digit entries.
  internal static func parse(_ list: String) -> Self? {
    let parsed = AnnouncementText.decode(list, maximum: entryCount)
    guard parsed.count == entryCount else { return nil }
    return Self(entries: parsed)
  }
}
