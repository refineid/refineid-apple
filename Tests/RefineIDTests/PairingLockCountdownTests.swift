// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@testable import RefineIDTestHost

/// A pairing lockout counts down from the instant it lifts and reads as
/// minutes and seconds from a minute on.
@Suite
internal struct PairingLockCountdownTests {
  /// The wait after the first lockout.
  private static let firstWait: TimeInterval = 2
  /// The wait after the second consecutive lockout.
  private static let secondWait: TimeInterval = 4
  /// A part of a second, to show the rounding.
  private static let fraction: TimeInterval = 0.25
  /// A wait past a minute and its seconds part.
  private static let longWait = 256
  private static let longWaitSeconds = "16"

  @Test("Remaining time rounds up to whole seconds and stops at zero")
  internal func roundsUpAndStopsAtZero() {
    let now = Date()
    let until = now.addingTimeInterval(Self.firstWait)
    #expect(
      PairingLockCountdown.remainingSeconds(until: until, at: now) == Int(Self.firstWait))
    #expect(
      PairingLockCountdown.remainingSeconds(
        until: until, at: now.addingTimeInterval(Self.fraction)) == Int(Self.firstWait))
    #expect(PairingLockCountdown.remainingSeconds(until: until, at: until) == 0)
    #expect(
      PairingLockCountdown.remainingSeconds(
        until: until, at: until.addingTimeInterval(Self.firstWait)) == 0)
  }

  @Test("The message changes every second and reads minutes from a minute on")
  internal func messageFollowsTheClock() {
    let now = Date()
    let until = now.addingTimeInterval(TimeInterval(Self.longWait))
    let long = PairingLockCountdown.message(until: until, at: now)
    let later = PairingLockCountdown.message(
      until: until, at: now.addingTimeInterval(PairingLockCountdown.tick))
    #expect(long.contains(Self.longWaitSeconds))
    #expect(!long.contains(String(Self.longWait)))
    #expect(long != later)
  }

  @Test("Each consecutive lockout doubles the wait; a success clears it")
  internal func backoffLiftsAtAnInstant() {
    let backoff = RappPairingBackoff()
    let now = Date()
    #expect(backoff.nextOfferDate(at: now) == nil)
    backoff.recordLockout(at: now)
    #expect(backoff.nextOfferDate(at: now) == now.addingTimeInterval(Self.firstWait))
    backoff.recordLockout(at: now)
    #expect(backoff.nextOfferDate(at: now) == now.addingTimeInterval(Self.secondWait))
    #expect(backoff.nextOfferDate(at: now.addingTimeInterval(Self.secondWait)) == nil)
    backoff.recordSuccess()
    #expect(backoff.nextOfferDate(at: now) == nil)
  }
}
