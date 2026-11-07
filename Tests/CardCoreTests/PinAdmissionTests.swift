// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// The counter check before a signature sends its PIN, over every probe
/// answer: the retry floor refuses one or two attempts left and an unreadable
/// counter, and a held PIN 1 is served only at the full allowance or on a
/// verified card.
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
      for attempts in (UInt8.zero + 1)..<RetryFloor.minimumAttemptsToProceed {
        #expect(
          PinAdmission(probe: try Self.remaining(attempts), spending: spending)
            == .retryFloor(.refuseLowAttempts))
      }
      #expect(
        PinAdmission(probe: .noInformation, spending: spending)
          == .retryFloor(.refuseUnreadable))
      #expect(
        PinAdmission(probe: .other(.zero), spending: spending) == .retryFloor(.refuseUnreadable))
    }
  }

  @Test
  internal func anEnteredPinGoesToTheCardAtNoTriesLeftOrBlocked() throws {
    for probe in [try Self.remaining(.zero), .locked, .invalidated] {
      #expect(PinAdmission(probe: probe, spending: .entered) == .proceed)
    }
  }

  @Test
  internal func aHeldPin1IsNeverSentForABlockedCounter() throws {
    #expect(
      PinAdmission(probe: try Self.remaining(.zero), spending: .heldPin1) == .credentialBlocked)
    #expect(PinAdmission(probe: .locked, spending: .heldPin1) == .credentialBlocked)
    #expect(PinAdmission(probe: .invalidated, spending: .heldPin1) == .credentialInvalidated)
  }
}
