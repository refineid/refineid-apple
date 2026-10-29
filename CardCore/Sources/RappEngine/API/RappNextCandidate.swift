// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a requester does after a pairing connection closed without its
/// custodian taking the code (RAPP v26.10.29 §4.2, "Trying Each Custodian in
/// Pairing Mode").
public enum RappNextCandidate: Equatable, Sendable {
  /// The custodian answered busy and is kept for another opening: open the
  /// next endpoint with ``RappPairingCandidates/nextEndpoint(nowMonotonicMs:)``,
  /// showing nothing.
  case deferred
  /// Remote use stopped being available: the requester's remote use is off,
  /// or a card is in a reader attached to it. The search ends and closes
  /// its connection; nothing is reported, and the code entry is offered
  /// again once remote use resumes (hierarchy specification §5.2).
  case interrupted
  /// No custodian has been tried and no endpoint is left to open: wait for
  /// discovery to find another, or report that none in pairing mode was
  /// found.
  case noneTried
  /// Every custodian tried refused the code, a custodian still busy at the
  /// connection limit counting as one that refused it: report it as not
  /// accepted, naming none of them.
  case notAccepted
  /// Open the next endpoint with
  /// ``RappPairingCandidates/nextEndpoint(nowMonotonicMs:)``.
  case tryNext

  /// The requester's next step after `next`, with `remoteUseAvailable`
  /// saying whether its remote use is on and no card is in a reader
  /// attached to it: the pairing machine's event decides it.
  internal init(_ next: NextCandidate, remoteUseAvailable: Bool) {
    switch next.pairingEvent(remoteUseAvailable: remoteUseAvailable).event {
    case .searchInterrupted:
      self = .interrupted

    case .lastCandidateFailed:
      self = .notAccepted

    case .attemptFailed:
      self = .tryNext

    case .candidateBusy:
      self = .deferred

    default:
      self = .noneTried
    }
  }
}
