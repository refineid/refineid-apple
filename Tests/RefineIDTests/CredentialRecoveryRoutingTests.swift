// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@testable import RefineIDTestHost

/// Which recovery the card management view offers for a set of retry
/// counters: one form for two blocked PINs, a single reset for one, and
/// the other-software guidance once the PUK is below the floor.
@MainActor
@Suite
internal struct CredentialRecoveryRoutingTests {
  private static let blocked: UInt8 = .zero
  private static let full = RetryCount.pristineAllowance
  private static let floor = RetryFloor.minimumAttemptsToProceed
  private static let belowFloor = RetryCount.lowAttemptCeiling

  @Test
  internal func bothPinsBlockedWithHealthyPukResetTogether() {
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.blocked, pin2: Self.blocked, puk: Self.full)
        == .resetBothPins)
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.blocked, pin2: Self.blocked, puk: Self.floor)
        == .resetBothPins)
  }

  @Test
  internal func oneBlockedPinKeepsItsSingleReset() {
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.blocked, pin2: Self.full, puk: Self.full)
        == .resetPin1)
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.full, pin2: Self.blocked, puk: Self.full)
        == .resetPin2)
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.blocked, pin2: Self.belowFloor, puk: Self.full)
        == .resetPin1)
  }

  @Test
  internal func pukBelowFloorKeepsTheGuidance() {
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.blocked, pin2: Self.blocked, puk: Self.belowFloor)
        == .useOtherSoftware)
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.blocked, pin2: Self.blocked, puk: Self.blocked)
        == .unrecoverable)
  }

  @Test
  internal func healthyCountersNeedNoRecovery() {
    #expect(
      CredentialRetryHealth.recovery(pin1: Self.full, pin2: Self.floor, puk: Self.full) == nil)
  }

  @Test
  internal func lockedReportsRouteToTheCombinedForm() throws {
    let puk = try #require(RetryCount(attemptsRemaining: Self.full))
    let health = CredentialRetryHealth.shared
    defer { health.clear() }
    health.update(CredentialProbeReport(pin1: .locked, pin2: .locked, puk: .remaining(puk)))
    #expect(health.recovery == .resetBothPins)
    #expect(CardManagementView.initialTask(for: health.recovery) == .resetPin1)
  }
}
