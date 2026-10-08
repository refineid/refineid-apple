// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Maps an authorization failure attributable to the peer.
///
/// A failure the peer caused is a protocol violation; the same failure caused
/// locally is a programming error, which is why the two mappings differ.
internal func enginePeerError(_ error: AuthorizationError) -> EngineError {
  switch error {
  case .journal(let journal):
    engineJournalError(journal)

  case .expired:
    .peerRequestExpired

  case .referenceMismatch:
    .authenticatedProtocolViolation(.referenceMismatch)

  case .wrongStage:
    .authenticatedProtocolViolation(.illegalOperationTransition)

  case .approvalMismatch, .invalidResult:
    .localInvariantFailure
  }
}

/// Maps an authorization failure the local caller caused.
internal func engineLocalError(_ error: AuthorizationError) -> EngineError {
  switch error {
  case .journal(let journal):
    engineJournalError(journal)

  case .expired, .approvalMismatch, .referenceMismatch, .wrongStage, .invalidResult:
    .invalidLocalTransition
  }
}

/// Maps a journal failure, keeping persistence distinct from an invariant
/// breach so a caller can tell a storage outage from a corrupted record.
internal func engineJournalError(_ error: JournalError) -> EngineError {
  switch error {
  case .persistence:
    .persistence

  case .invalidState, .requestHashMismatch, .alreadyTransmitted:
    .localInvariantFailure
  }
}
