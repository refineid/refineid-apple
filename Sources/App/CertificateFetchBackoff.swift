// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// When the background read of the paired phone's certificate may ask
/// the phone again.
///
/// Every read reaches the phone as a card request and can hold it for
/// its whole card wait. The first two failures are retried on their
/// own after a short gap, for a phone that was only briefly out of
/// reach. After that no read is scheduled: the phone's next
/// advertisement starts one, but only once a gap that doubles from
/// half a minute to five minutes has passed. An explicit retry, a
/// launch, or a new pairing starts over.
internal struct CertificateFetchBackoff: Equatable, Sendable {
  // MARK: Static Properties

  /// Failures followed by a quick retry.
  internal static let quickRetries = 2

  private static let quickDelaySeconds: Int64 = 2
  private static let firstSlowDelaySeconds: Int64 = 30
  private static let longestDelaySeconds: Int64 = 300
  private static let growth: Int64 = 2

  private static let quickDelay: Duration = .seconds(quickDelaySeconds)
  private static let firstSlowDelay: Duration = .seconds(firstSlowDelaySeconds)
  private static let longestDelay: Duration = .seconds(longestDelaySeconds)

  // MARK: Properties

  /// Reads that ended without a certificate since the last start over.
  internal private(set) var failures = 0

  private var notBefore: ContinuousClock.Instant?

  /// Whether the failure count still earns a scheduled quick retry.
  internal var schedulesQuickRetry: Bool {
    failures > 0 && failures <= Self.quickRetries
  }

  // MARK: Static Functions

  /// The gap after `failures` consecutive failed reads.
  internal static func delay(afterFailures failures: Int) -> Duration {
    guard failures > quickRetries else { return quickDelay }
    var delay = firstSlowDelay
    for _ in 0..<(failures - quickRetries - 1) {
      delay *= Self.growth
      if delay >= longestDelay { return longestDelay }
    }
    return delay
  }

  // MARK: Functions

  /// Whether a read may start at `now`.
  internal func permits(at now: ContinuousClock.Instant) -> Bool {
    guard let notBefore else { return true }
    return now >= notBefore
  }

  /// Records a read that ended without a certificate at `now`.
  internal mutating func recordFailure(at now: ContinuousClock.Instant) {
    failures += 1
    notBefore = now.advanced(by: Self.delay(afterFailures: failures))
  }

  /// Starts over, so the next read goes out at once.
  internal mutating func reset() {
    failures = 0
    notBefore = nil
  }
}
