// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// When a card session opened for one remote operation stays open for the
/// next, and when it ends.
///
/// A session is kept while the card can still be served, for at most
/// ``idleLimitSeconds`` after its last operation where the hold sets an
/// idle limit and, where the platform limits a session's life, for at most
/// that life, so the next request reuses the secure channel the card
/// already holds instead of opening the field and running PACE again.
/// Anything that makes the channel untrustworthy ends it at once.
internal struct CardSessionHold: Equatable {
  /// Why a held session ended.
  internal enum Ending: Equatable {
    case appBackgrounded
    case cardLeft
    case channelUnprepared
    case closedByOwner
    case idleExpired
    case keepAliveUnanswered
    case lastSessionClosed
    case operationUnanswered
    case promptShown
    case servingStopped
    case sessionAged
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

  /// Seconds a reader session survives after its last operation.
  ///
  /// Long enough for the next request of one login, which follows the
  /// first within a few seconds; short enough that a card left in the
  /// reader is not held by a session nobody uses.
  internal static let readerIdleLimitSeconds: Int64 = 10

  /// Seconds a near-field session may be held from its opening.
  ///
  /// Core NFC invalidates a reader session 60 seconds after it begins
  /// (Apple, WWDC 2019 session 715, "the existing 60-second maximum scan
  /// time still exists for each reader session";
  /// `readerSessionInvalidationErrorSessionTimeout`); a held session ends
  /// before that, so the next request opens a fresh one instead of
  /// meeting an invalidated field mid-command.
  internal static let nearFieldSessionLimitSeconds: Int64 = 50

  /// Seconds a held near-field channel goes without an exchange before
  /// the holder sends it one harmless command.
  ///
  /// The system takes an idle slot away six to eight seconds after the
  /// last exchange; a command every two seconds keeps it up until the
  /// platform's own limit on the field's life.
  internal static let nearFieldKeepAliveSeconds: Int64 = 2

  /// Wait between two looks at an idle near field, which is how soon a
  /// card taken off the phone ends the hold.
  internal static let nearFieldLookInterval: Duration = .seconds(1)

  /// Milliseconds in one second, for the clocks.
  internal static let millisecondsPerSecond: Int64 = 1_000

  /// The session's longest life in seconds, or nil where the platform
  /// sets none.
  internal let sessionLimitSeconds: Int64?

  /// Seconds the session survives after its last operation, or nil where
  /// only the platform ends an idle session.
  internal let idleLimitSeconds: Int64?

  internal private(set) var state: State = .closed

  /// When the session was opened.
  internal private(set) var openedAtMs: Int64?

  /// When the session last became idle: on opening, and after each
  /// operation.
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

  /// A hold whose session lives at most `sessionLimitSeconds` and idles
  /// at most `idleLimitSeconds`; nil sets no such limit.
  internal init(sessionLimitSeconds: Int64?, idleLimitSeconds: Int64?) {
    self.sessionLimitSeconds = sessionLimitSeconds
    self.idleLimitSeconds = idleLimitSeconds
  }

  /// An exclusive card session was opened at `nowMs`.
  internal mutating func sessionOpened(nowMs: Int64) {
    state = .open(channelPrepared: false, busy: false)
    openedAtMs = nowMs
    idleSinceMs = nowMs
  }

  /// PACE finished and the application is selected on the channel.
  internal mutating func channelPrepared() {
    guard case .open(_, let busy) = state else { return }
    state = .open(channelPrepared: true, busy: busy)
  }

  /// An operation wants the channel at `nowMs`; a session too old to
  /// finish one ends instead.
  internal mutating func startsOperation(nowMs: Int64) -> Verdict {
    guard case .open(let prepared, _) = state else { return .keep }
    if aged(nowMs: nowMs) { return close(.sessionAged) }
    state = .open(channelPrepared: prepared, busy: true)
    idleSinceMs = nil
    return .keep
  }

  /// An operation returned; `answered` says the card answered it.
  internal mutating func operationFinished(answered: Bool, nowMs: Int64) -> Verdict {
    guard case .open(let prepared, _) = state else { return .keep }
    guard answered else { return close(.operationUnanswered) }
    state = .open(channelPrepared: prepared, busy: false)
    idleSinceMs = nowMs
    return .keep
  }

  /// The clock was read.
  internal mutating func tick(nowMs: Int64) -> Verdict {
    guard case .open(_, busy: false) = state else { return .keep }
    if aged(nowMs: nowMs) { return close(.sessionAged) }
    guard let idleLimitSeconds, let idleSinceMs else { return .keep }
    let limitMs = idleLimitSeconds * Self.millisecondsPerSecond
    guard nowMs - idleSinceMs >= limitMs else { return .keep }
    return close(.idleExpired)
  }

  /// Something outside the hold ended the session for `ending`.
  internal mutating func end(_ ending: Ending) -> Verdict {
    close(ending)
  }

  private func aged(nowMs: Int64) -> Bool {
    guard let sessionLimitSeconds, let openedAtMs else { return false }
    return nowMs - openedAtMs >= sessionLimitSeconds * Self.millisecondsPerSecond
  }

  private mutating func close(_ ending: Ending) -> Verdict {
    guard isOpen else { return .keep }
    state = .closed
    openedAtMs = nil
    idleSinceMs = nil
    return .end(ending)
  }
}
