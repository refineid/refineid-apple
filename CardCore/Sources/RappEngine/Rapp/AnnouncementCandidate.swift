// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One hint and when its pairing was last used.
internal struct AnnouncementCandidate: Equatable {
  internal let hint: Data
  internal let lastUsedMilliseconds: UInt64
}
