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
  case startPairing = "start_pairing"
  case offerExpiredOrCancelled = "offer_expired_or_cancelled"
  case attemptStarted = "attempt_started"
  case codeEntered = "code_entered"
  case attemptFailed = "attempt_failed"
  case lastAttemptFailed = "last_attempt_failed"
  case keyConfirmed = "key_confirmed"
  case handshakeAuthenticated = "handshake_authenticated"
  case handshakeFailed = "handshake_failed"
  case helloVerified = "hello_verified"
  case bothConfirmed = "both_confirmed"
  /// Also a `pairing.stored` naming another `pair_id`.
  case deniedAbortedOrTimedOut = "denied_aborted_or_timed_out"
  case peerStorageConfirmed = "peer_storage_confirmed"
  /// Produced by the session machine entering healthy.
  case sessionHealthy = "session_healthy"
  /// Produced by the session machine entering closed.
  case sessionClosed = "session_closed"
  case forgetPairing = "forget_pairing"
  /// Produced by the next session sending the close as its first message.
  case revocationNoticeSent = "revocation_notice_sent"
  /// `revocation_notice_days` after the revocation.
  case noticeWindowExpired = "notice_window_expired"
  /// `session.close` with reason `pairing_revoked`, also in place of
  /// `session.ready`.
  case peerRevocationNotice = "peer_revocation_notice"
}

// swiftlint:enable sorted_enum_cases
