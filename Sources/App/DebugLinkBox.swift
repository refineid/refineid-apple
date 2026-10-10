// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import Foundation

  /// Holds the link a transport closure forwards to once it exists.
  internal final class DebugLinkBox<Link: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Link?

    internal var value: Link? {
      get { lock.withLock { stored } }
      set { lock.withLock { stored = newValue } }
    }
  }

#endif
