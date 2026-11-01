// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Activation-scheme classification, the preflight, and the
/// changed-since-manufacture flag (FINEID S4-1 §4.6, S1 v4.2 §3.15.3).
@Suite
internal struct ActivationTests {
  /// The published cutover, 13 January 2026, as its UTC midnight.
  private static let cutover = Date(timeIntervalSince1970: 1_768_262_400)

  /// One calendar day in seconds, for stepping around the cutover.
  private static let day: TimeInterval = 86_400

  @Test
  internal func issuanceDateDecidesTheScheme() {
    #expect(
      ActivationScheme.classify(issuedOn: Self.cutover - Self.day)
        == .activationCodeIsPuk
    )
    #expect(
      ActivationScheme.classify(issuedOn: Self.cutover)
        == .presetActivationPin
    )
    #expect(
      ActivationScheme.classify(issuedOn: Self.cutover + 365 * Self.day)
        == .presetActivationPin
    )
  }

  @Test
  internal func entryDigitCountFollowsTheScheme() {
    #expect(ActivationScheme.activationCodeIsPuk.activationEntryDigitCount == 8)
    #expect(ActivationScheme.presetActivationPin.activationEntryDigitCount == 7)
  }

  @Test
  internal func cardNeedsActivationWhileEitherPinDoes() {
    #expect(!CardActivationNeeds(pin1: false, pin2: false).any)
    #expect(CardActivationNeeds(pin1: true, pin2: false).any)
    #expect(CardActivationNeeds(pin1: false, pin2: true).any)
  }

  /// A factory-fresh §4.6.1 card ships both PINs blocked and can
  /// report that as an exhausted counter; the unchanged flag marks it
  /// as awaiting activation whatever the counter says.
  @Test
  internal func activationCodePreflightFollowsTheChangedFlag() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let exhausted = try #require(RetryCount(attemptsRemaining: 0))
    let probes: [RetryProbeOutcome?] = [
      .remaining(exhausted), .remaining(five), .locked, .invalidated, .verified, nil,
    ]
    for probe in probes {
      #expect(
        ActivationPreflight.evaluate(
          scheme: .activationCodeIsPuk,
          probe: probe,
          changeRecord: .unchanged
        ) == .ready
      )
      #expect(
        ActivationPreflight.evaluate(
          scheme: .activationCodeIsPuk,
          probe: probe,
          changeRecord: .changed
        ) == .alreadyActivated
      )
    }
  }

  /// Without the flag, a blocked, invalidated or exhausted PIN is
  /// served the activation: it is the same PUK reset recovery sends.
  @Test
  internal func activationCodePreflightFallsBackToABlockedCounter() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let exhausted = try #require(RetryCount(attemptsRemaining: 0))
    let blocked: [RetryProbeOutcome] = [.remaining(exhausted), .locked, .invalidated]
    for probe in blocked {
      #expect(
        ActivationPreflight.evaluate(
          scheme: .activationCodeIsPuk,
          probe: probe,
          changeRecord: .unreadable
        ) == .ready
      )
    }
    let usable: [RetryProbeOutcome?] = [
      .remaining(five), .verified, .noInformation, .other(0), nil,
    ]
    for probe in usable {
      #expect(
        ActivationPreflight.evaluate(
          scheme: .activationCodeIsPuk,
          probe: probe,
          changeRecord: .unreadable
        ) == .alreadyActivated
      )
    }
  }

  @Test
  internal func presetPinPreflightFollowsTheChangedFlagAlone() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    // A healthy counter is the expected fresh state and proves nothing:
    // the flag dominates in every combination.
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        probe: .remaining(five),
        changeRecord: .changed
      ) == .alreadyActivated
    )
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        probe: .remaining(five),
        changeRecord: .unchanged
      ) == .ready
    )
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        probe: .locked,
        changeRecord: .unreadable
      ) == .ready
    )
  }

  /// An interrupted activation leaves one PIN set and one waiting,
  /// and the preflight judges each on its own: the card stays ready
  /// through the waiting PIN while the set one reads as activated, so
  /// the flow finishes the card instead of refusing it - or worse,
  /// setting the set one again.
  @Test
  internal func aHalfActivatedCardReadsPerPin() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let exhausted = try #require(RetryCount(attemptsRemaining: 0))
    // Old scheme: PIN 1 was unblocked and set, PIN 2 is still blocked
    // in its factory state.
    #expect(
      ActivationPreflight.evaluate(
        scheme: .activationCodeIsPuk,
        probe: .remaining(five),
        changeRecord: .changed
      ) == .alreadyActivated
    )
    #expect(
      ActivationPreflight.evaluate(
        scheme: .activationCodeIsPuk,
        probe: .remaining(exhausted),
        changeRecord: .unchanged
      ) == .ready
    )
    // New scheme: PIN 1's changed flag is set, PIN 2's is not.
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        probe: .verified,
        changeRecord: .changed
      ) == .alreadyActivated
    )
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        probe: .remaining(five),
        changeRecord: .unchanged
      ) == .ready
    )
  }

  @Test
  internal func changedFlagParsesItsThreeAnswers() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let unchanged = WireHex.data("DF210405FFA501DF2F0100")
    let changed = WireHex.data("DF210405FFA501DF2F0101")
    let unknownFlag = WireHex.data("DF210405FFA501DF2F0102")
    let absent = WireHex.data("DF210405FFA501")

    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: unchanged)
        == .unchanged
    )
    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: changed)
        == .changed
    )
    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: unknownFlag)
        == .unreadable
    )
    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: absent)
        == .unreadable
    )
    // The same body still answers the retry counter.
    #expect(
      CredentialAttributes.retryCounter(fromResponseBody: unchanged) == five
    )
  }
}
