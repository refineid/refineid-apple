// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Pairing component event.
///
/// Raw values are the formal model's event names, so a Swift case and a model
/// rule are compared without a translation table.
internal enum PairingEvent: String, CaseIterable, Sendable {
  case createOffer = "create_offer"
  case offerScanned = "offer_scanned"
  case candidateConnected = "candidate_connected"
  case offerExpiredOrCancelled = "offer_expired_or_cancelled"
  case handshakeAuthenticated = "handshake_authenticated"
  case handshakeFailed = "handshake_failed"
  case bothUsersConfirmed = "both_users_confirmed"
  /// The peer's `pairing.stored` arrived with the derived pair identifier.
  case peerStorageConfirmed = "peer_storage_confirmed"
  case deniedAbortedOrTimedOut = "denied_aborted_or_timed_out"
  /// Produced by the session machine entering healthy.
  case sessionHealthy = "session_healthy"
  /// Produced by the session machine entering closed.
  case sessionClosed = "session_closed"
  case forgetPairing = "forget_pairing"
  case authenticatedProtocolViolation = "authenticated_protocol_violation"
  case localRevoke = "local_revoke"
  /// Produced by a peer close carrying pairing_revoked or protocol_violation.
  case peerRevocationNotice = "peer_revocation_notice"
}

// swiftlint:enable sorted_enum_cases
