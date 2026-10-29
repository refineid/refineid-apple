// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine

/// Which session a dial's first frame opens on the custodian (RAPP
/// v26.10.29 §2.2.1, §8.3).
///
/// Every dial whose session preamble routes to a pairing this custodian
/// serves opens a session of its own, however many are open already, under
/// that pairing or any other (STPA CC-58): an open session is never a
/// reason to refuse, hold or displace one. A dial is refused only for what
/// routing refuses: a pairing preamble on the session listener or server, a
/// preamble that names no pairing served here, or one whose nonce was
/// routed before.
internal struct CustodianSessionAdmission: Sendable {
  /// What becomes of one dial.
  internal enum Verdict: Equatable, Sendable {
    /// The dial opens a session over the pairing at this index of the
    /// served records.
    case open(Int)
    /// A pairing preamble; the session listener and server pair nothing.
    case refusedPairingAttempt
    /// The preamble names no pairing served here, or replays one routed
    /// before.
    case refusedUnrouted
  }

  /// The pairings dials may route to.
  internal var records: [RappPairRecord] = []

  /// Remembers the nonces routed here, refusing a replay.
  private var router = RappSessionRouter()

  /// The verdict on a dial over `transportProfile` whose first frame is
  /// `preamble`.
  internal func admit(_ preamble: Data, transportProfile: String) -> Verdict {
    switch router.route(transportProfile: transportProfile, preamble: preamble, records: records) {
    case .session(let index) where records.indices.contains(index):
      .open(index)

    case .pairing:
      .refusedPairingAttempt

    default:
      .refusedUnrouted
    }
  }

  /// Forgets every nonce routed so far, for a listener or server started
  /// afresh.
  internal mutating func forgetRouted() {
    router = RappSessionRouter()
  }
}
