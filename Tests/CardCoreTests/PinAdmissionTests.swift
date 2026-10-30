// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// The counter check before a signature sends its PIN, over every probe
/// answer: the retry floor serves five, four or three attempts left, and a
/// held PIN 1 only the full allowance or a verified card.
@Suite
internal struct PinAdmissionTests {
  private static func remaining(_ attempts: UInt8) throws -> RetryProbeOutcome {
    .remaining(try #require(RetryCount(attemptsRemaining: attempts)))
  }

  @Test
  internal func anEnteredPinIsServedDownToTheFloor() throws {
    for attempts in RetryFloor.minimumAttemptsToProceed...RetryCount.pristineAllowance {
      #expect(
        PinAdmission(probe: try Self.remaining(attempts), spending: .entered) == .proceed)
    }
    #expect(PinAdmission(probe: .verified, spending: .entered) == .proceed)
  }

  @Test
  internal func aHeldPin1IsServedOnlyAtTheFullAllowance() throws {
    #expect(
      PinAdmission(
        probe: try Self.remaining(RetryCount.pristineAllowance), spending: .heldPin1)
        == .proceed)
    for attempts in RetryFloor.minimumAttemptsToProceed..<RetryCount.pristineAllowance {
      #expect(
        PinAdmission(probe: try Self.remaining(attempts), spending: .heldPin1)
          == .heldPin1Unconfirmed)
    }
  }

  @Test
  internal func aHeldPin1IsServedOnAVerifiedCard() {
    // A successful VERIFY sets the try counter to its limit (S1 v4.2
    // section 3.5), so the verified answer proves a full counter.
    #expect(PinAdmission(probe: .verified, spending: .heldPin1) == .proceed)
  }

  @Test
  internal func theFloorRefusesBeforeTheHeldCheck() throws {
    for spending in [PinAdmission.Spending.entered, .heldPin1] {
      for attempts in UInt8.zero..<RetryFloor.minimumAttemptsToProceed {
        let verdict: RetryFloorVerdict =
          attempts == .zero ? .refuseBlocked : .refuseLowAttempts
        #expect(
          PinAdmission(probe: try Self.remaining(attempts), spending: spending)
            == .retryFloor(verdict))
      }
    }
  }

  @Test
  internal func aLockedInvalidatedOrUnreadableCounterIsRefused() {
    for spending in [PinAdmission.Spending.entered, .heldPin1] {
      #expect(PinAdmission(probe: .locked, spending: spending) == .credentialBlocked)
      #expect(PinAdmission(probe: .invalidated, spending: spending) == .credentialInvalidated)
      #expect(
        PinAdmission(probe: .noInformation, spending: spending)
          == .retryFloor(.refuseUnreadable))
      #expect(
        PinAdmission(probe: .other(.zero), spending: spending) == .retryFloor(.refuseUnreadable))
    }
  }
}
