// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a dial that routed to a pairing may open a session on this
/// phone, which serves one session at a time whatever transport carries it.
///
/// A busy session, one with an operation in flight or a handshake still
/// coming up, is never displaced, so an operation is never cut short. An
/// idle session is handed over at once to its own pairing, the requester's
/// app and token extension sharing one, and to another pairing only once
/// it has idled past the hold, so computers do not steal the phone from
/// each other between operations (R-59).
internal enum HolderSessionAdmission: Equatable, Sendable {
  /// No session is open, or the open one is handed over.
  case admit
  /// The open session carries an operation or is still coming up.
  case refuseBusy
  /// The open session is another pairing's and has idled less than the
  /// hold.
  case refuseHeld

  /// Whether the dial gets the session.
  internal var admits: Bool {
    self == .admit
  }

  /// The verdict for a dial routed to `incoming`, while the open session
  /// runs over `pairing` (nil while none is open) and has idled since
  /// `idleSince` (nil while it is busy or coming up).
  internal static func decide(
    incoming: Data,
    pairing: Data?,
    idleSince: ContinuousClock.Instant?,
    now: ContinuousClock.Instant,
    hold: Duration
  ) -> Self {
    guard let pairing else { return .admit }
    guard let idleSince else { return .refuseBusy }
    if pairing == incoming { return .admit }
    return now - idleSince >= hold ? .admit : .refuseHeld
  }
}
