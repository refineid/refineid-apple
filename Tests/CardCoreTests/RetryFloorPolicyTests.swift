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
    // Zero: blocked. Nothing is sent; the PUK resets it.
    let blocked = try #require(RetryCount(attemptsRemaining: 0))
    #expect(RetryFloor.evaluate(freshReading: blocked) == .refuseBlocked)
  }

  @Test
  internal func anUnreadableCounterFailsClosed() {
    // No reading is not permission. A probe that cannot be classified
    // must never become an attempt.
    #expect(RetryFloor.evaluate(freshReading: nil) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .noInformation) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .other(0)) == .refuseUnreadable)
    #expect(RetryFloor.evaluate(probeOutcome: .invalidated) == .refuseUnreadable)
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
    // A locked credential is refused like a zero count, and told apart
    // from an unreadable counter so the refusal can name the PUK.
    #expect(RetryFloor.evaluate(probeOutcome: .locked) == .refuseBlocked)
  }

  @Test
  internal func thePukAtNoTriesLeftGoesToTheCard() throws {
    // The PUK is judged for the credential it is: one or two tries
    // left and an unreadable counter refuse as for a PIN, but none
    // left or blocked proceed. The card answers for itself and spends
    // nothing, and the software cannot tell a PUK from an activation
    // code in the holder's hand, so it must not close a recovery the
    // card would allow.
    let none = try #require(RetryCount(attemptsRemaining: 0))
    #expect(RetryFloor.evaluate(probeOutcome: .remaining(none), presenting: .puk) == .proceed)
    #expect(RetryFloor.evaluate(probeOutcome: .locked, presenting: .puk) == .proceed)
    for remaining in [UInt8(1), 2] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(
        RetryFloor.evaluate(probeOutcome: .remaining(count), presenting: .puk)
          == .refuseLowAttempts)
    }
    for remaining in [UInt8(3), 4, 5] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(RetryFloor.evaluate(probeOutcome: .remaining(count), presenting: .puk) == .proceed)
    }
    #expect(RetryFloor.evaluate(probeOutcome: .verified, presenting: .puk) == .proceed)
    for unreadable in [RetryProbeOutcome.noInformation, .other(0), .invalidated] {
      #expect(RetryFloor.evaluate(probeOutcome: unreadable, presenting: .puk) == .refuseUnreadable)
    }
  }

  @Test
  internal func activationLetsTheCardAnswerAnExhaustedCredential() throws {
    // The last-tries rule, for whatever an activation presents: one or
    // two tries left and an unreadable counter refuse; none left and
    // blocked go to the card, which spends nothing.
    let none = try #require(RetryCount(attemptsRemaining: 0))
    #expect(RetryFloor.evaluateLastTries(probeOutcome: .remaining(none)) == .proceed)
    #expect(RetryFloor.evaluateLastTries(probeOutcome: .locked) == .proceed)
    for remaining in [UInt8(1), 2] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(RetryFloor.evaluateLastTries(probeOutcome: .remaining(count)) == .refuseLowAttempts)
    }
    for remaining in [UInt8(3), 4, 5] {
      let count = try #require(RetryCount(attemptsRemaining: remaining))
      #expect(RetryFloor.evaluateLastTries(probeOutcome: .remaining(count)) == .proceed)
    }
    #expect(RetryFloor.evaluateLastTries(probeOutcome: .verified) == .proceed)
    for unreadable in [RetryProbeOutcome.noInformation, .other(0), .invalidated] {
      #expect(RetryFloor.evaluateLastTries(probeOutcome: unreadable) == .refuseUnreadable)
    }
  }

  @Test
  internal func aPinAtNoTriesLeftStaysRefused() throws {
    // The PIN floor is unchanged: a blocked PIN is refused before the
    // card is asked, and the PUK resets it.
    let none = try #require(RetryCount(attemptsRemaining: 0))
    for role in [CredentialRole.pin1, .pin2] {
      #expect(
        RetryFloor.evaluate(probeOutcome: .remaining(none), presenting: role) == .refuseBlocked)
      #expect(RetryFloor.evaluate(probeOutcome: .locked, presenting: role) == .refuseBlocked)
    }
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
    #expect(RetryFloor.evaluate(freshReading: state.pin1) == .refuseBlocked)
    #expect(RetryFloor.evaluate(freshReading: state.pin2) == .refuseLowAttempts)
    #expect(RetryFloor.evaluate(freshReading: state.puk) == .proceed)
  }
}
