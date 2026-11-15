// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_TIMESTAMP_CONFIG

  import Foundation

  /// Doubles for driving the settings draft's probes.
  internal enum TimestampSettingsProbeDoubles {
    /// A rendezvous for holding one probe mid-flight.
    ///
    /// The lock guards every property.
    internal final class ProbeGate: @unchecked Sendable {
      private let lock = NSLock()
      private var calls = 0
      private var entered = false
      private var released = false
      private var continuation: CheckedContinuation<Void, Never>?

      /// Whether a call parked or passed through.
      internal var hasEntered: Bool {
        lock.withLock { entered }
      }

      /// Count this call; the first call's number is one.
      internal func nextCall() -> Int {
        lock.withLock {
          calls += 1
          return calls
        }
      }

      /// Hold until released, unless already released.
      internal func suspend() async {
        let skip = lock.withLock { () -> Bool in
          entered = true
          return released
        }
        if skip {
          return
        }
        await withCheckedContinuation { continuation in
          let resumeNow = lock.withLock { () -> Bool in
            if released {
              return true
            }
            self.continuation = continuation
            return false
          }
          if resumeNow {
            continuation.resume()
          }
        }
      }

      /// Let the parked call through; later calls pass.
      internal func release() {
        let held: CheckedContinuation<Void, Never>? = lock.withLock {
          released = true
          let held = continuation
          continuation = nil
          return held
        }
        held?.resume()
      }
    }

    /// The probed addresses, in order.
    internal actor CallLog {
      internal private(set) var targets: [String] = []

      internal func record(_ target: String) {
        targets.append(target)
      }
    }
  }

#endif
