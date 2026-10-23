// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import Foundation

  @testable import RefineID

  /// A same-account directory that counts its removals and is reachable or
  /// not as a test says.
  internal final class RecordingSameAccountDirectory: SameAccountDirectory,
    @unchecked Sendable
  {
    private let lock = NSLock()
    private var reachable: Bool
    private var removed = 0

    /// How often the directory was asked to remove the phones.
    internal var removals: Int {
      lock.withLock { removed }
    }

    internal init(reachable: Bool) {
      self.reachable = reachable
    }

    /// Makes the directory reachable, or not, from now on.
    internal func setReachable(_ value: Bool) {
      lock.withLock { reachable = value }
    }

    internal func removeComplementaryDevices() -> Bool {
      lock.withLock {
        removed += 1
        return reachable
      }
    }
  }

#endif
