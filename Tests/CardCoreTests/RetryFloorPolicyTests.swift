// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// The production guard, stated once as a table.
///
/// Every PIN-bearing operation reads the counter of the credential it
/// is about to present, in the same card transaction, and proceeds
/// only on this rule. The test exists because the rule is the thing
/// standing between a curious afternoon - or a bug in this code - and
/// a card that has to go back to the issuer.
@Suite
internal struct RetryFloorPolicyTests {
  @Test
  internal func theFloorProceedsOnlyAtThreeOrMoreAttempts() throws {
    // Three or more: room to be wrong and try again.
    for remaining in [UInt8(3), 4, 5] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(RetryFloor.evaluate(freshReading: count) == .proceed)
    }
    // One or two: refused. Never spend a near-last attempt.
    for remaining in [UInt8(1), 2] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(RetryFloor.evaluate(freshReading: count) == .refuseLowAttempts)
    }
    // Zero: blocked. The command goes to the card, which answers itself.
    let blocked = try #require(RetryCount(attemptsRemaining: 0))
    #expect(RetryFloor.evaluate(freshReading: blocked) == .proceed)
  }

  @Test
  internal func anUnreadableCounterFailsClosed() {
    // No reading is not permission. A probe that cannot be classified
    // must never become an attempt.
    #expect(RetryFloor.evaluate(freshReading: nil) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .noInformation) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .other(0)) == .refuseUnreadable)
  }

  @Test
  internal func aVerifiedCredentialProceeds() {
    // A successful VERIFY resets the retry counter to its maximum
    // (S1 v4.2 §3.5), so the probe's 9000 proves a full counter even
    // though it carries no count. The organization card's global
    // credentials (S4-2 v4.0 §4.2) stay verified across re-selecting
    // the application, so every signature after the first in one
    // session sees exactly this answer.
    #expect(RetryFloor.evaluate(probeOutcome: .verified) == .proceed)
  }

  @Test
  internal func aLockedCredentialIsRefusedAsBlocked() {
    // A locked credential goes on like a zero count: the card answers,
    // and an unreadable counter stays refused.
    #expect(RetryFloor.evaluate(probeOutcome: .locked) == .proceed)
    #expect(RetryFloor.evaluate(probeOutcome: .invalidated) == .proceed)
  }

  @Test
  internal func everyCredentialTakesTheOneRule() throws {
    // One or two tries left and an unreadable counter refuse; none left
    // and blocked go to the card, which answers for itself and spends
    // nothing, and the software cannot tell which code is in the holder's
    // hand, so it must not close a recovery the card would allow.
    let none = try #require(RetryCount(attemptsRemaining: 0))
    for role in [CredentialRole.pin1, .pin2, .puk] {
      #expect(RetryFloor.evaluate(probeOutcome: .remaining(none), presenting: role) == .proceed)
      #expect(RetryFloor.evaluate(probeOutcome: .locked, presenting: role) == .proceed)
      #expect(RetryFloor.evaluate(probeOutcome: .invalidated, presenting: role) == .proceed)
      for remaining in [UInt8(1), 2] {
        let count = try #require(RetryCount(attemptsRemaining: remaining))
        #expect(
          RetryFloor.evaluate(probeOutcome: .remaining(count), presenting: role)
            == .refuseLowAttempts)
      }
      for remaining in [UInt8(3), 4, 5] {
        let count = try #require(RetryCount(attemptsRemaining: remaining))
        #expect(RetryFloor.evaluate(probeOutcome: .remaining(count), presenting: role) == .proceed)
      }
      for unreadable in [RetryProbeOutcome.noInformation, .other(0)] {
        #expect(
          RetryFloor.evaluate(probeOutcome: unreadable, presenting: role) == .refuseUnreadable)
      }
    }
  }

  @Test
  internal func aVerifiedPinIsServedAndAVerifiedPukIsUnreadable() {
    for role in [CredentialRole.pin1, .pin2] {
      #expect(RetryFloor.evaluate(probeOutcome: .verified, presenting: role) == .proceed)
    }
    #expect(RetryFloor.evaluate(probeOutcome: .verified, presenting: .puk) == .refuseUnreadable)
  }

  @Test
  internal func eachCredentialIsJudgedOnItsOwnCounter() throws {
    // The three counters are never combined. A PUK with room is what
    // permits an unblock, whatever the blocked PIN says; a PIN2 near
    // its limit refuses a signature while PIN1 is untouched.
    let blocked = try #require(RetryCount(attemptsRemaining: 0))
    let low = try #require(RetryCount(attemptsRemaining: 2))
    let healthy = try #require(RetryCount(attemptsRemaining: 5))
    let state = CredentialRetryState(pin1: blocked, pin2: low, puk: healthy)
    #expect(RetryFloor.evaluate(freshReading: state.pin1) == .proceed)
    #expect(RetryFloor.evaluate(freshReading: state.pin2) == .refuseLowAttempts)
    #expect(RetryFloor.evaluate(freshReading: state.puk) == .proceed)
  }
}
