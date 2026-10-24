// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// How often the background certificate read may ask the phone.
@Suite
internal struct CertificateFetchBackoffTests {
  private enum Fixture {
    static let quick: Duration = .seconds(2)
    static let firstSlow: Duration = .seconds(30)
    static let longest: Duration = .seconds(300)
  }

  /// A fresh backoff lets the first read out at once.
  @Test
  internal func freshBackoffPermits() {
    #expect(CertificateFetchBackoff().permits(at: .now))
  }

  /// The first failures are retried quickly, later ones ever more slowly.
  @Test
  internal func delaysGrowToTheCap() {
    #expect(CertificateFetchBackoff.delay(afterFailures: 1) == Fixture.quick)
    #expect(CertificateFetchBackoff.delay(afterFailures: 2) == Fixture.quick)
    #expect(CertificateFetchBackoff.delay(afterFailures: 3) == Fixture.firstSlow)
    #expect(CertificateFetchBackoff.delay(afterFailures: 4) == Fixture.firstSlow * 2)
    #expect(CertificateFetchBackoff.delay(afterFailures: 20) == Fixture.longest)
  }

  /// A failed read holds the next one back until its gap has passed.
  @Test
  internal func failureHoldsTheNextRead() {
    var backoff = CertificateFetchBackoff()
    let now = ContinuousClock.now
    backoff.recordFailure(at: now)
    #expect(!backoff.permits(at: now))
    #expect(backoff.permits(at: now.advanced(by: Fixture.quick)))
  }

  /// The third failure waits out the slow gap.
  @Test
  internal func laterFailuresWaitLonger() {
    var backoff = CertificateFetchBackoff()
    let now = ContinuousClock.now
    backoff.recordFailure(at: now)
    backoff.recordFailure(at: now)
    backoff.recordFailure(at: now)
    #expect(!backoff.permits(at: now.advanced(by: Fixture.quick)))
  }

  /// Starting over lets the next read out at once.
  @Test
  internal func resetStartsOver() {
    var backoff = CertificateFetchBackoff()
    let now = ContinuousClock.now
    for _ in 0..<5 {
      backoff.recordFailure(at: now)
    }
    backoff.reset()
    #expect(backoff.failures == 0)
    #expect(backoff.permits(at: now))
  }
}
