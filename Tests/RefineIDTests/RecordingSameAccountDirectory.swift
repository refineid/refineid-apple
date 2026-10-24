// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import Foundation

  @testable import RefineIDTestHost

  /// A same-account directory that records what it was asked to remove,
  /// still holds those phones or not as a test says, and holds each removal
  /// until the test releases it when told to.
  internal final class RecordingSameAccountDirectory: SameAccountDirectory,
    @unchecked Sendable
  {
    private let lock = NSLock()
    private var reachable: Bool
    private var holding = false
    private var requests: [Set<Data>] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var duringRemoval: (@Sendable () -> Void)?

    /// The pairings each removal was asked for, in order.
    internal var removals: [Set<Data>] {
      lock.withLock { requests }
    }

    /// How many removals wait for ``release()``.
    internal var waiting: Int {
      lock.withLock { held.count }
    }

    internal init(reachable: Bool) {
      self.reachable = reachable
    }

    /// Makes the phones leave, or stay, from now on.
    internal func setReachable(_ value: Bool) {
      lock.withLock { reachable = value }
    }

    /// Holds every removal from now on until ``release()``.
    internal func hold() {
      lock.withLock { holding = true }
    }

    /// Lets every held removal go, and holds none from now on.
    internal func release() {
      let released = lock.withLock {
        holding = false
        defer { held = [] }
        return held
      }
      for continuation in released {
        continuation.resume()
      }
    }

    /// Runs `action` while the next removal is under way.
    internal func onRemoval(_ action: @escaping @Sendable () -> Void) {
      lock.withLock { duringRemoval = action }
    }

    internal func removeDevices(pairedThrough pairIDs: Set<Data>) async -> Bool {
      let (mustWait, action) = lock.withLock {
        requests.append(pairIDs)
        defer { duringRemoval = nil }
        return (holding, duringRemoval)
      }
      action?()
      if mustWait {
        await withCheckedContinuation { continuation in
          lock.withLock { held.append(continuation) }
        }
      }
      return lock.withLock { reachable }
    }
  }

#endif
