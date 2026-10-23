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
  /// On the requester: the endpoint opened did not take the code, because
  /// its custodian refused it or it served no offer the requester could try.
  case attemptFailed = "attempt_failed"
  case lastAttemptFailed = "last_attempt_failed"
  /// Every custodian the requester tried refused the code, and no endpoint
  /// is left to open.
  case lastCandidateFailed = "last_candidate_failed"
  /// No endpoint served an offer the requester could try, and its search
  /// ended.
  case noCustodianTried = "no_custodian_tried"
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
  /// Produced in place of `session_closed` on a custodian whose session the
  /// requester closed with reason `service_withdrawn`: the computer withdrew
  /// (§4.5 item 9).
  case peerWithdrawalNotice = "peer_withdrawal_notice"
}

// swiftlint:enable sorted_enum_cases
