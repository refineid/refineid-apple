// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Why a pairing attempt ended.
///
/// Once the handshake authenticates the peer, a violation invalidates the
/// offer without producing a pair record: no failure here ever stores a
/// pairing.
internal enum PairingError: Error, Equatable {
  case candidateNotUnique
  case confirmationIncomplete
  case duplicateMessage
  case grantMismatch
  case helloIncomplete
  case invalidGrantSet
  case message(MessageFieldError)
  case missingPairIdentifier
  case noise
  case offer(PairingOfferError)
  case offerExpired
  case open(RappOpenFailure)
  /// The peer's `pairing.stored` names another pairing (RAPP v26.10.22
  /// §4.3 item 4); the pairing aborts and the stored record is revoked.
  case pairIdentifierMismatch
  case pairRecord(PairRecordError)
  case parameterMismatch
  case roleViolation
  /// The pairing is not active: one of the two storage confirmations is
  /// missing.
  case storageUnconfirmed
  case unexpectedMessage
  case unsupportedProfile
}
