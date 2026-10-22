// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a requester does after a pairing connection closed without its
/// custodian taking the code (RAPP v26.10.22 §4.2, "Trying Each Custodian in
/// Pairing Mode").
public enum RappNextCandidate: Equatable, Sendable {
  /// No custodian has been tried and no endpoint is left to open: wait for
  /// discovery to find another, or report that none in pairing mode was
  /// found.
  case noneTried
  /// Every custodian tried refused the code: report it as not accepted,
  /// naming none of them.
  case notAccepted
  /// Open the next endpoint with ``RappPairingCandidates/nextEndpoint()``.
  case tryNext

  internal init(_ next: NextCandidate) {
    switch next {
    case .noneTried:
      self = .noneTried

    case .notAccepted:
      self = .notAccepted

    case .tryNext:
      self = .tryNext
    }
  }
}
