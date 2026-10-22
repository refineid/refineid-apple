// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RefineID

/// A near field whose platform behaves as measured on an iPhone.
///
/// The slot goes away when idle for a few seconds, and the field ends some
/// seconds after it was given however busy it is kept. The card in it
/// keeps PIN 1 verified for one signature only, as a FINEID card does.
internal enum WarmNearFieldFakes {
  /// What the card was sent.
  internal enum Command: Equatable {
    case keepAlive
    case pace
    case probe
    case sign
    case verify
  }

  /// What one operation ended with.
  internal enum Outcome: NearFieldOutcome, Equatable {
    /// The card refused the signature: no PIN was verified for it.
    case refused
    /// The card signed.
    case signed
    /// The card did not answer.
    case unanswered

    internal var cardAnswered: Bool {
      self != .unanswered
    }

    internal var isResult: Bool {
      self == .signed
    }
  }

  /// A clock in milliseconds that moves only when the test moves it.
  internal final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var nowMs: Int64 = 0

    internal func read() -> Int64 {
      lock.withLock { nowMs }
    }

    internal func advance(byMs milliseconds: Int64) {
      lock.withLock { nowMs += milliseconds }
    }
  }

  /// The card, which outlives every field it is held in.
  internal final class Card: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: Clock
    private var log: [Command] = []
    private var verified = false
    private var answers = true
    private var lastCommandMs: Int64 = 0

    /// Every command the card was sent, in order.
    internal var commands: [Command] {
      lock.withLock { log }
    }

    /// When the card last answered a command.
    internal var lastAnsweredMs: Int64 {
      lock.withLock { lastCommandMs }
    }

    internal init(clock: Clock) {
      self.clock = clock
    }

    /// The card stops answering anything.
    internal func goMute() {
      lock.withLock { answers = false }
    }

    /// Records `command`; false when the card does not answer.
    internal func send(_ command: Command) -> Bool {
      let now = clock.read()
      return lock.withLock {
        guard answers else { return false }
        log.append(command)
        lastCommandMs = now
        return true
      }
    }

    /// VERIFY PIN 1: the next signature may use the key.
    internal func verifyPin1() -> Bool {
      guard send(.verify) else { return false }
      lock.withLock { verified = true }
      return true
    }

    /// A signature, which spends the verification it needs.
    internal func sign() -> Outcome {
      guard send(.sign) else { return .unanswered }
      return lock.withLock {
        defer { verified = false }
        return verified ? .signed : .refused
      }
    }

    /// The command log with the keep-alives left out.
    internal func work() -> [Command] {
      commands.filter { $0 != .keepAlive }
    }
  }

  /// One field the fake platform gave.
  internal final class Field: NearField, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: Clock
    private let card: Card
    private let idleLifeMs: Int64
    private let fieldLifeMs: Int64
    private let openedAtMs: Int64
    private var removed = false
    private var ended = false
    private var lines: [NearFieldSheetLine] = []

    internal var holdsValidCard: Bool {
      !isMissing
    }

    internal var isMissing: Bool {
      let now = clock.read()
      let lastExchangeMs = max(openedAtMs, card.lastAnsweredMs)
      return lock.withLock {
        ended || removed
          || now - lastExchangeMs >= idleLifeMs
          || now - openedAtMs >= fieldLifeMs
      }
    }

    internal var stateName: String {
      isMissing ? "missing" : "validCard"
    }

    /// Whether the holder's side ended the field.
    internal var isEnded: Bool {
      lock.withLock { ended }
    }

    /// What the sheet said, in order.
    internal var sheetLines: [NearFieldSheetLine] {
      lock.withLock { lines }
    }

    internal init(clock: Clock, card: Card, idleLifeMs: Int64, fieldLifeMs: Int64) {
      self.clock = clock
      self.card = card
      self.idleLifeMs = idleLifeMs
      self.fieldLifeMs = fieldLifeMs
      self.openedAtMs = clock.read()
    }

    /// The holder takes the card off the phone.
    internal func removeCard() {
      lock.withLock { removed = true }
    }

    internal func end() {
      lock.withLock { ended = true }
    }

    internal func endChannel(_: Card) {
      // The fake card keeps no session state to end.
    }

    internal func keepAlive(_ channel: Card) -> Bool {
      !isMissing && channel.send(.keepAlive)
    }

    internal func prepareChannel(cardAccessNumber _: String) -> Card? {
      guard !isMissing, card.send(.pace) else { return nil }
      return card
    }

    internal func show(_ line: NearFieldSheetLine) {
      lock.withLock { lines.append(line) }
    }
  }

  /// The platform: gives a new field for every request, each one a tap.
  internal final class Reader: @unchecked Sendable {
    internal let clock = Clock()
    internal let card: Card
    private let lock = NSLock()
    private let idleLifeMs: Int64
    private let fieldLifeMs: Int64
    private var given: [Field] = []

    /// How many fields were opened.
    internal var opens: Int {
      lock.withLock { given.count }
    }

    /// The field given last.
    internal var latest: Field? {
      lock.withLock { given.last }
    }

    internal init(idleLifeMs: Int64, fieldLifeMs: Int64) {
      self.idleLifeMs = idleLifeMs
      self.fieldLifeMs = fieldLifeMs
      self.card = Card(clock: clock)
    }

    internal func open() -> Field {
      let field = Field(
        clock: clock, card: card, idleLifeMs: idleLifeMs, fieldLifeMs: fieldLifeMs)
      lock.withLock { given.append(field) }
      return field
    }
  }

  /// What the warm field reported.
  internal final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var endingLog: [CardSessionHold.Ending] = []
    private var reuseCount = 0

    /// Why each field ended, in order.
    internal var endings: [CardSessionHold.Ending] {
      lock.withLock { endingLog }
    }

    /// How many operations ran on a field already open.
    internal var reuses: Int {
      lock.withLock { reuseCount }
    }

    internal func record(_ event: NearFieldEvent) {
      lock.withLock {
        switch event {
        case .ended(let ending, _):
          endingLog.append(ending)

        case .reused:
          reuseCount += 1

        case .notOpened, .opened, .operationFinished, .operationStarted:
          break
        }
      }
    }
  }
}
