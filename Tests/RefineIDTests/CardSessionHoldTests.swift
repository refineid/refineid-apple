// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// When a held card session is reused and when it ends.
@Suite
internal struct CardSessionHoldTests {
  private static let idleLimitMs =
    CardSessionHold.readerIdleLimitSeconds * CardSessionHold.millisecondsPerSecond
  private static let sessionLimitMs =
    CardSessionHold.nearFieldSessionLimitSeconds * CardSessionHold.millisecondsPerSecond
  private static let momentMs: Int64 = 1

  private static func opened(
    nowMs: Int64 = 0, sessionLimitSeconds: Int64? = nil
  ) -> CardSessionHold {
    var hold = CardSessionHold(
      sessionLimitSeconds: sessionLimitSeconds,
      idleLimitSeconds: CardSessionHold.readerIdleLimitSeconds)
    hold.sessionOpened(nowMs: nowMs)
    hold.channelPrepared()
    return hold
  }

  @Test("An answered operation keeps the prepared channel for the next")
  internal func answeredOperationKeepsTheChannel() {
    var hold = Self.opened()
    #expect(hold.startsOperation(nowMs: 0) == .keep)
    #expect(!hold.reusesChannel)
    #expect(hold.operationFinished(answered: true, nowMs: 0) == .keep)
    #expect(hold.reusesChannel)
    #expect(hold.tick(nowMs: Self.idleLimitMs - Self.momentMs) == .keep)
    #expect(hold.isOpen)
  }

  @Test("An operation the card did not answer ends the hold")
  internal func unansweredOperationEndsTheHold() {
    var hold = Self.opened()
    #expect(hold.startsOperation(nowMs: 0) == .keep)
    #expect(hold.operationFinished(answered: false, nowMs: 0) == .end(.operationUnanswered))
    #expect(!hold.isOpen)
  }

  @Test("The idle limit ends a hold nobody used")
  internal func idleLimitEndsTheHold() {
    var hold = Self.opened()
    #expect(hold.startsOperation(nowMs: 0) == .keep)
    #expect(hold.operationFinished(answered: true, nowMs: 0) == .keep)
    #expect(hold.tick(nowMs: Self.idleLimitMs) == .end(.idleExpired))
    #expect(!hold.isOpen)
  }

  @Test("A session prepared ahead of any request idles from its opening")
  internal func preparedSessionIdlesFromItsOpening() {
    var hold = Self.opened(nowMs: 0)
    #expect(hold.tick(nowMs: Self.idleLimitMs - Self.momentMs) == .keep)
    #expect(hold.tick(nowMs: Self.idleLimitMs) == .end(.idleExpired))
    #expect(!hold.isOpen)
  }

  @Test("A busy hold does not expire")
  internal func busyHoldDoesNotExpire() {
    var hold = Self.opened()
    #expect(hold.startsOperation(nowMs: 0) == .keep)
    #expect(hold.tick(nowMs: Self.idleLimitMs * 2) == .keep)
    #expect(hold.isOpen)
  }

  @Test("A near-field session ends before the system invalidates it")
  internal func nearFieldSessionEndsBeforeTheSystemLimit() {
    var hold = Self.opened(
      nowMs: 0, sessionLimitSeconds: CardSessionHold.nearFieldSessionLimitSeconds)
    #expect(hold.startsOperation(nowMs: Self.sessionLimitMs - Self.momentMs) == .keep)
    let lastMoment = Self.sessionLimitMs - Self.momentMs
    #expect(hold.operationFinished(answered: true, nowMs: lastMoment) == .keep)
    #expect(hold.startsOperation(nowMs: Self.sessionLimitMs) == .end(.sessionAged))
    #expect(!hold.isOpen)
    var idle = Self.opened(
      nowMs: 0, sessionLimitSeconds: CardSessionHold.nearFieldSessionLimitSeconds)
    #expect(idle.tick(nowMs: Self.sessionLimitMs) == .end(.sessionAged))
  }

  @Test("An aged session is closed, and the operation that found it so changes nothing more")
  internal func agedSessionStaysClosed() {
    var hold = Self.opened(
      nowMs: 0, sessionLimitSeconds: CardSessionHold.nearFieldSessionLimitSeconds)
    #expect(hold.startsOperation(nowMs: Self.sessionLimitMs) == .end(.sessionAged))
    #expect(hold.state == .closed)
    #expect(hold.operationFinished(answered: true, nowMs: Self.sessionLimitMs) == .keep)
    #expect(hold.state == .closed)
    #expect(!hold.reusesChannel)
    hold.sessionOpened(nowMs: Self.sessionLimitMs)
    hold.channelPrepared()
    #expect(hold.reusesChannel)
  }

  @Test("A reader session has no life limit of its own")
  internal func readerSessionHasNoLifeLimit() {
    var hold = Self.opened(nowMs: 0)
    #expect(hold.startsOperation(nowMs: Self.sessionLimitMs * 2) == .keep)
    #expect(hold.isOpen)
  }

  @Test("Card removal, background and an unanswered keep-alive end the hold at once")
  internal func removalBackgroundAndFailureEndTheHold() {
    var left = Self.opened()
    #expect(left.end(.cardLeft) == .end(.cardLeft))
    var backgrounded = Self.opened()
    #expect(backgrounded.end(.appBackgrounded) == .end(.appBackgrounded))
    var failed = Self.opened()
    #expect(failed.end(.keepAliveUnanswered) == .end(.keepAliveUnanswered))
    #expect(!left.isOpen && !backgrounded.isOpen && !failed.isOpen)
  }

  @Test("A near-field hold idles until the platform or its session limit ends it")
  internal func nearFieldHoldHasNoIdleLimit() {
    var hold = CardSessionHold(
      sessionLimitSeconds: CardSessionHold.nearFieldSessionLimitSeconds,
      idleLimitSeconds: nil)
    hold.sessionOpened(nowMs: 0)
    hold.channelPrepared()
    #expect(hold.tick(nowMs: Self.sessionLimitMs - Self.momentMs) == .keep)
    #expect(hold.reusesChannel)
    #expect(hold.tick(nowMs: Self.sessionLimitMs) == .end(.sessionAged))
  }

  @Test("A closed hold ignores events")
  internal func closedHoldIgnoresEvents() {
    var hold = CardSessionHold(
      sessionLimitSeconds: nil, idleLimitSeconds: CardSessionHold.readerIdleLimitSeconds)
    #expect(hold.end(.cardLeft) == .keep)
    #expect(hold.startsOperation(nowMs: 0) == .keep)
    #expect(hold.operationFinished(answered: true, nowMs: 0) == .keep)
    #expect(hold.tick(nowMs: Self.idleLimitMs) == .keep)
    #expect(!hold.reusesChannel)
  }

  @Test("A new session starts without a prepared channel")
  internal func newSessionIsUnprepared() {
    var hold = CardSessionHold(
      sessionLimitSeconds: nil, idleLimitSeconds: CardSessionHold.readerIdleLimitSeconds)
    hold.sessionOpened(nowMs: 0)
    #expect(hold.isOpen)
    #expect(!hold.reusesChannel)
    hold.channelPrepared()
    #expect(hold.reusesChannel)
  }
}
