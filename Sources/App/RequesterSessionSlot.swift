// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The one session a requester holds with its phone, whatever carries it.
///
/// A computer holds at most one session to its phone across its transports
/// and processes: a new dial goes only while none is being dialled or open,
/// and not before the wait that follows a session that ended or a dial that
/// brought none up (``RedialBackoff``). A session that comes up starts the
/// wait over, and so does the phone newly appearing.
internal struct RequesterSessionSlot: Equatable, Sendable {
  /// What the slot holds.
  internal enum State: Equatable, Sendable {
    /// A dial over the transport is under way.
    case dialing(RequesterTransport)
    /// No session is dialled or open.
    case empty
    /// The session over the transport is up.
    case open(RequesterTransport)
  }

  // MARK: Properties

  /// What the slot holds now.
  internal private(set) var state = State.empty

  /// The waits after failures.
  private var backoff = RedialBackoff()

  /// The earliest moment the next dial may go; nil when at once.
  internal private(set) var nextDialAt: ContinuousClock.Instant?

  // MARK: Computed Properties

  /// The transport the held session runs over; nil while none is held.
  internal var transport: RequesterTransport? {
    switch state {
    case .dialing(let transport), .open(let transport):
      transport

    case .empty:
      nil
    }
  }

  /// Whether the held session is up.
  internal var isEstablished: Bool {
    if case .open = state { return true }
    return false
  }

  // MARK: Functions

  /// Whether a dial may go at `now`: no session is dialled or open, and
  /// the wait after the last failure is over.
  internal func mayDial(at now: ContinuousClock.Instant) -> Bool {
    guard state == .empty else { return false }
    guard let nextDialAt else { return true }
    return now >= nextDialAt
  }

  /// A dial over `transport` started; false, and nothing changes, when the
  /// slot is not free for one at `now`.
  internal mutating func dial(over transport: RequesterTransport, at now: ContinuousClock.Instant)
    -> Bool
  {
    guard mayDial(at: now) else { return false }
    state = .dialing(transport)
    return true
  }

  /// The dialled session came up and confirmed the phone: the wait starts
  /// over.
  internal mutating func established() {
    guard let transport else { return }
    state = .open(transport)
    backoff.reset()
    nextDialAt = nil
  }

  /// The held session ended, or its dial brought none up, at `now`; the
  /// next dial waits the back-off.
  internal mutating func ended(at now: ContinuousClock.Instant) {
    state = .empty
    nextDialAt = now + backoff.recordFailure()
  }

  /// This side let the session go: the slot is free, the wait unchanged.
  internal mutating func released() {
    state = .empty
  }

  /// The phone newly appeared: the next dial may go at once.
  internal mutating func startOver() {
    backoff.reset()
    nextDialAt = nil
  }
}
