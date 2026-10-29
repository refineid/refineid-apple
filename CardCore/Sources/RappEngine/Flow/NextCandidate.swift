// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the requester does after a pairing connection closed without its
/// custodian taking the code (RAPP v26.10.29 §4.2, "Trying Each Custodian in
/// Pairing Mode").
internal enum NextCandidate: Equatable, Sendable {
  /// The custodian answered busy and is kept for another opening: open the
  /// next endpoint (``PairingCandidates/nextEndpoint(nowMilliseconds:)``),
  /// which hands this one out again once its wait has passed.
  case deferred
  /// No custodian has been tried, none answered busy, and no endpoint is
  /// left to open: wait for discovery to find another, or report that none
  /// in pairing mode was found.
  case noneTried
  /// Every custodian tried refused the code, a custodian that answered busy
  /// counting as one that refused it: report it as not accepted, naming
  /// none of them.
  case notAccepted
  /// Open the next endpoint
  /// (``PairingCandidates/nextEndpoint(nowMilliseconds:)``).
  case tryNext

  /// The pairing-machine event of this outcome on the requester, with the
  /// guards it carries.
  ///
  /// `remoteUseAvailable` says whether the requester's remote use is on and
  /// no card is in a reader attached to it. Without it
  /// no further custodian is tried and the search ends as
  /// ``PairingEvent/searchInterrupted``, unless every custodian tried already
  /// refused the code (hierarchy specification §5.2). ``noneTried`` is
  /// ``PairingEvent/noCustodianTried`` once the requester's search ends.
  internal func pairingEvent(remoteUseAvailable: Bool) -> (
    event: PairingEvent, guards: RappGuards
  ) {
    if self != .notAccepted, !remoteUseAvailable {
      return (.searchInterrupted, .noneSatisfied)
    }
    return switch self {
    case .deferred:
      (.candidateBusy, RappGuards(satisfied: [.untriedPairingCandidate]))

    case .notAccepted:
      (.lastCandidateFailed, .noneSatisfied)

    case .noneTried:
      (.noCustodianTried, .noneSatisfied)

    case .tryNext:
      (.attemptFailed, RappGuards(satisfied: [.untriedPairingCandidate]))
    }
  }
}
