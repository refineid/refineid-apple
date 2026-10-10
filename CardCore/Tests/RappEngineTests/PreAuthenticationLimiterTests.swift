// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RappEngine

@Suite("RAPP v26.10.9 pre-authentication rate limit (section 3.3)")
internal struct PreAuthenticationLimiterTests {
  private static let start: UInt64 = 10_000
  private static let spacing = RappPreAuthenticationLimiter.minimumSpacingMilliseconds

  @Test("At most one attempt is admitted per 500 ms")
  internal func spacing() {
    let limiter = RappPreAuthenticationLimiter()
    #expect(Self.spacing == 500)
    #expect(limiter.admit(nowMonotonicMs: Self.start))
    #expect(!limiter.admit(nowMonotonicMs: Self.start))
    #expect(!limiter.admit(nowMonotonicMs: Self.start + Self.spacing - 1))
    #expect(limiter.admit(nowMonotonicMs: Self.start + Self.spacing))
  }

  @Test("A refused attempt does not move the window")
  internal func refusalKeepsTheWindow() {
    let limiter = RappPreAuthenticationLimiter()
    #expect(limiter.admit(nowMonotonicMs: Self.start))
    #expect(!limiter.admit(nowMonotonicMs: Self.start + Self.spacing - 1))
    #expect(limiter.admit(nowMonotonicMs: Self.start + Self.spacing))
  }

  @Test("A clock reading before the last admission is refused")
  internal func backwardsClockIsRefused() {
    let limiter = RappPreAuthenticationLimiter()
    #expect(limiter.admit(nowMonotonicMs: Self.start))
    #expect(!limiter.admit(nowMonotonicMs: Self.start - 1))
  }
}
