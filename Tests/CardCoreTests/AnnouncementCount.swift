// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A count a C callback can raise from any thread.
internal final class AnnouncementCount: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  internal var total: Int { lock.withLock { value } }

  internal func increment() { lock.withLock { value += 1 } }
}
