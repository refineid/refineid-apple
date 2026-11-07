// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One cached list as the index records it.
internal struct TrustedListCacheRecord: Codable, Equatable, Sendable {
  /// Where the list was fetched from.
  internal let location: String

  /// When it was fetched.
  internal let fetchedAt: Date

  /// Its next update; nil for a closed list.
  internal let nextUpdate: Date?

  /// The file holding its bytes, beside the index.
  internal let file: String
}
