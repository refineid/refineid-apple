// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// When a held card session is reused and when it ends.
@Suite
internal struct CardSessionHoldTests {
  private static let limitMs =
    CardSessionHold.idleLimitSeconds * CardSessionHold.millisecondsPerSecond
  private static let momentMs: Int64 = 1

  private static func opened() -> CardSessionHold {
    var hold = CardSessionHold()
    hold.sessionOpened()
    hold.channelPrepared()
    return hold
  }

  @Test("An answered operation keeps the prepared channel for the next")
  internal func answeredOperationKeepsTheChannel() {
    var hold = Self.opened()
    hold.operationStarted()
    #expect(!hold.reusesChannel)
    #expect(hold.operationFinished(answered: true, nowMs: 0) == .keep)
    #expect(hold.reusesChannel)
    #expect(hold.tick(nowMs: Self.limitMs - Self.momentMs) == .keep)
    #expect(hold.isOpen)
  }

  @Test("An operation the card did not answer ends the hold")
  internal func unansweredOperationEndsTheHold() {
    var hold = Self.opened()
    hold.operationStarted()
    #expect(hold.operationFinished(answered: false, nowMs: 0) == .end(.operationUnanswered))
    #expect(!hold.isOpen)
  }

  @Test("The idle limit ends a hold nobody used")
  internal func idleLimitEndsTheHold() {
    var hold = Self.opened()
    hold.operationStarted()
    #expect(hold.operationFinished(answered: true, nowMs: 0) == .keep)
    #expect(hold.tick(nowMs: Self.limitMs) == .end(.idleExpired))
    #expect(!hold.isOpen)
  }

  @Test("A busy hold does not expire")
  internal func busyHoldDoesNotExpire() {
    var hold = Self.opened()
    hold.operationStarted()
    #expect(hold.tick(nowMs: Self.limitMs * 2) == .keep)
    #expect(hold.isOpen)
  }

  @Test("Card removal, background and a failed command end the hold at once")
  internal func removalBackgroundAndFailureEndTheHold() {
    var left = Self.opened()
    #expect(left.cardLeft() == .end(.cardLeft))
    var backgrounded = Self.opened()
    #expect(backgrounded.appBackgrounded() == .end(.appBackgrounded))
    var failed = Self.opened()
    #expect(failed.commandFailed() == .end(.commandFailed))
    #expect(!left.isOpen && !backgrounded.isOpen && !failed.isOpen)
  }

  @Test("A closed hold ignores events")
  internal func closedHoldIgnoresEvents() {
    var hold = CardSessionHold()
    #expect(hold.cardLeft() == .keep)
    #expect(hold.operationFinished(answered: true, nowMs: 0) == .keep)
    #expect(hold.tick(nowMs: Self.limitMs) == .keep)
    #expect(!hold.reusesChannel)
  }

  @Test("A new session starts without a prepared channel")
  internal func newSessionIsUnprepared() {
    var hold = CardSessionHold()
    hold.sessionOpened()
    #expect(hold.isOpen)
    #expect(!hold.reusesChannel)
    hold.channelPrepared()
    #expect(hold.reusesChannel)
  }
}
