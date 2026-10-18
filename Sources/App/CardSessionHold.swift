// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// When a card session opened for one remote operation stays open for the
/// next, and when it ends.
///
/// A session is kept while the card can still be served, for at most
/// ``idleLimitSeconds`` after its last operation, so the next request
/// reuses the secure channel and the verified state the card already
/// holds instead of opening the field and running PACE again. Anything
/// that makes the channel untrustworthy ends it at once.
internal struct CardSessionHold: Equatable {
  /// Why a held session ended.
  internal enum Ending: Equatable {
    case appBackgrounded
    case cardLeft
    case closedByOwner
    case commandFailed
    case idleExpired
    case operationUnanswered
  }

  /// What the owner does after an event.
  internal enum Verdict: Equatable {
    case end(Ending)
    case keep
  }

  /// Where the session is.
  internal enum State: Equatable {
    case closed
    case open(channelPrepared: Bool, busy: Bool)
  }

  /// Seconds a held session survives after its last operation.
  ///
  /// Long enough for the next request of one login (a renegotiation, a
  /// second resource, a document after the login), short enough that a
  /// card left on the phone is released within the system NFC slot's
  /// own lifetime.
  internal static let idleLimitSeconds: Int64 = 25

  /// Milliseconds in one second, for the idle clock.
  internal static let millisecondsPerSecond: Int64 = 1_000

  internal private(set) var state: State = .closed

  /// When the last operation finished, while the session idles.
  internal private(set) var idleSinceMs: Int64?

  /// Whether a session is held.
  internal var isOpen: Bool {
    if case .open = state { return true }
    return false
  }

  /// Whether the next operation can reuse the secure channel.
  internal var reusesChannel: Bool {
    if case .open(channelPrepared: true, busy: false) = state { return true }
    return false
  }

  /// An exclusive card session was opened.
  internal mutating func sessionOpened() {
    state = .open(channelPrepared: false, busy: false)
    idleSinceMs = nil
  }

  /// PACE finished and the application is selected on the channel.
  internal mutating func channelPrepared() {
    guard case .open(_, let busy) = state else { return }
    state = .open(channelPrepared: true, busy: busy)
  }

  /// An operation took the channel.
  internal mutating func operationStarted() {
    guard case .open(let prepared, _) = state else { return }
    state = .open(channelPrepared: prepared, busy: true)
    idleSinceMs = nil
  }

  /// An operation returned; `answered` says the card answered it.
  internal mutating func operationFinished(answered: Bool, nowMs: Int64) -> Verdict {
    guard case .open(let prepared, _) = state else { return .keep }
    guard answered else { return close(.operationUnanswered) }
    state = .open(channelPrepared: prepared, busy: false)
    idleSinceMs = nowMs
    return .keep
  }

  /// The idle clock was read.
  internal mutating func tick(nowMs: Int64) -> Verdict {
    guard case .open(_, busy: false) = state, let idleSinceMs else { return .keep }
    let limitMs = Self.idleLimitSeconds * Self.millisecondsPerSecond
    guard nowMs - idleSinceMs >= limitMs else { return .keep }
    return close(.idleExpired)
  }

  internal mutating func cardLeft() -> Verdict {
    close(.cardLeft)
  }

  internal mutating func appBackgrounded() -> Verdict {
    close(.appBackgrounded)
  }

  internal mutating func commandFailed() -> Verdict {
    close(.commandFailed)
  }

  internal mutating func closedByOwner() -> Verdict {
    close(.closedByOwner)
  }

  private mutating func close(_ ending: Ending) -> Verdict {
    guard isOpen else { return .keep }
    state = .closed
    idleSinceMs = nil
    return .end(ending)
  }
}
