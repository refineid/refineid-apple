// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// Spaces timestamp requests across separate documents and containers so
/// batch, repeated, or scripted signing honors the authority's fair-use delay.
///
/// Each signed document or container acquires its own ``DocumentSession``
/// through ``makeDocumentSession()``. A document reserves a monotonic send
/// slot before its first timestamp request and sleeps outside the lock, so
/// neither waiting nor remote HTTP roundtrips hold a process-wide lock.
/// Follow-up timestamps on the same document (such as an archive timestamp
/// after a signature timestamp) proceed without intra-document delay once an
/// earlier exchange on that document succeeded, while extending the spacing
/// horizon for subsequent documents.
internal final class TimestampThrottle: Sendable {
  /// Tracks timestamp exchanges belonging to one document or container.
  internal final class DocumentSession: Sendable {
    private let throttle: TimestampThrottle
    private let canFollowUpImmediately = OSAllocatedUnfairLock(initialState: false)

    fileprivate init(throttle: TimestampThrottle) {
      self.throttle = throttle
    }

    /// Runs one timestamp exchange under this document's spacing rules.
    internal func perform<Value>(
      _ exchange: () async throws -> Value
    ) async throws -> Value {
      let followsUpImmediately = canFollowUpImmediately.withLock { current in
        let previous = current
        current = false
        return previous
      }
      if !followsUpImmediately {
        let scheduled = throttle.reserveSlot()
        try await throttle.awaitUntil(scheduled)
      }
      defer {
        throttle.recordCompletion()
      }
      let value = try await exchange()
      canFollowUpImmediately.withLock { $0 = true }
      return value
    }
  }

  /// Mutable schedule state protected by an unfair lock.
  private struct State {
    /// Earliest instant the next separate document may start timestamping.
    var nextSlot: ContinuousClock.Instant?
  }

  /// Minimum fair-use spacing in seconds between separate documents.
  internal static let minimumDocumentSpacingSeconds = 15

  /// Minimum fair-use spacing between timestamp requests for separate documents.
  internal static let minimumDocumentSpacing: Duration = .seconds(
    minimumDocumentSpacingSeconds
  )

  /// Process-wide throttle shared across signing flows.
  internal static let shared = TimestampThrottle(spacing: minimumDocumentSpacing)

  private let now: @Sendable () -> ContinuousClock.Instant
  private let sleep: @Sendable (Duration) async throws -> Void
  private let spacing: Duration
  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Creates a throttle backed by the monotonic system clock and task sleep.
  internal convenience init(spacing: Duration) {
    self.init(
      now: { ContinuousClock.now },
      sleep: { duration in try await Task.sleep(for: duration) },
      spacing: spacing
    )
  }

  /// Creates a throttle with injectable clock and sleep functions for tests.
  internal init(
    now: @escaping @Sendable () -> ContinuousClock.Instant,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    spacing: Duration
  ) {
    precondition(spacing >= .zero, "Timestamp spacing must not be negative.")
    self.now = now
    self.sleep = sleep
    self.spacing = spacing
  }

  /// Creates a session representing one document or container being signed.
  internal func makeDocumentSession() -> DocumentSession {
    DocumentSession(throttle: self)
  }

  private func reserveSlot() -> ContinuousClock.Instant {
    let instant = now()
    return state.withLock { current in
      let scheduled: ContinuousClock.Instant
      if let nextSlot = current.nextSlot, instant < nextSlot {
        scheduled = nextSlot
      } else {
        scheduled = instant
      }
      current.nextSlot = scheduled.advanced(by: spacing)
      return scheduled
    }
  }

  private func cancelUnusedTailSlot(_ scheduled: ContinuousClock.Instant) {
    let reservedHorizon = scheduled.advanced(by: spacing)
    state.withLock { current in
      if current.nextSlot == reservedHorizon {
        current.nextSlot = scheduled
      }
    }
  }

  private func recordCompletion() {
    let afterCompletion = now().advanced(by: spacing)
    state.withLock { current in
      if let nextSlot = current.nextSlot, afterCompletion <= nextSlot {
        return
      }
      current.nextSlot = afterCompletion
    }
  }

  private func awaitUntil(_ target: ContinuousClock.Instant) async throws {
    do {
      while true {
        try Task.checkCancellation()
        let remaining = now().duration(to: target)
        if remaining <= .zero || spacing <= .zero {
          return
        }
        try await sleep(remaining)
      }
    } catch {
      cancelUnusedTailSlot(target)
      throw error
    }
  }
}
