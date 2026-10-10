// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A pairing's hint and when that pairing was last used; records announce
/// the most recently used pairings.
public struct RappAnnouncementCandidate: Equatable, Sendable {
  /// The pairing's hint for the record being built.
  public var hint: Data
  /// When the pairing last had a session, in milliseconds since 1970.
  public var lastUsedMs: UInt64

  internal var engineCandidate: AnnouncementCandidate {
    AnnouncementCandidate(hint: hint, lastUsedMilliseconds: lastUsedMs)
  }

  /// A candidate announcing `hint`, last used at `lastUsedMs`.
  public init(hint: Data, lastUsedMs: UInt64) {
    self.hint = hint
    self.lastUsedMs = lastUsedMs
  }
}
