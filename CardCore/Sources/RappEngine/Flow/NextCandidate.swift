// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the requester does after a pairing connection closed without its
/// custodian taking the code (RAPP v26.10.22 §4.2, "Trying Each Custodian in
/// Pairing Mode").
internal enum NextCandidate: Equatable, Sendable {
  /// No custodian has been tried and no endpoint is left to open: wait for
  /// discovery to find another, or report that none in pairing mode was
  /// found.
  case noneTried
  /// Every custodian tried refused the code: report it as not accepted,
  /// naming none of them.
  case notAccepted
  /// Open the next endpoint (``PairingCandidates/nextEndpoint()``).
  case tryNext

  /// The pairing-machine event of this outcome on the requester, with the
  /// guards it carries. ``noneTried`` is ``PairingEvent/noCustodianTried``
  /// once the requester's search ends.
  internal var pairingEvent: (event: PairingEvent, guards: RappGuards) {
    switch self {
    case .noneTried:
      (.noCustodianTried, .noneSatisfied)

    case .notAccepted:
      (.lastCandidateFailed, .noneSatisfied)

    case .tryNext:
      (.attemptFailed, RappGuards(satisfied: [.untriedPairingCandidate]))
    }
  }
}
