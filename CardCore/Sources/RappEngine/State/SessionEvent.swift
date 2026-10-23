// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Session component event.
///
/// Raw values are the formal model's event names, so a Swift case and a model
/// rule are compared without a translation table.
internal enum SessionEvent: String, CaseIterable, Sendable {
  case connect = "connect"
  case preambleReceived = "preamble_received"
  case transportConnected = "transport_connected"
  case transportFailed = "transport_failed"
  case handshakeComplete = "handshake_complete"
  /// The pairing is revoking: the close is the session's first message.
  case handshakeCompleteWhileRevoking = "handshake_complete_while_revoking"
  /// A received `session.close`; on the requester also a revoking
  /// custodian's close in place of `session.ready`.
  case peerCloseReceived = "peer_close_received"
  case readyVerified = "ready_verified"
  /// Before authentication: the connection closes, nothing stored changes.
  case candidateFailure = "candidate_failure"
  /// Version, `session_id`, sequence or message misuse.
  case authenticatedProtocolViolation = "authenticated_protocol_violation"
  /// `liveness_ping_after_silence_ms` without a message.
  case peerSilent = "peer_silent"
  /// `session_silence_limit_ms` without a message.
  case silenceLimitReached = "silence_limit_reached"
  case userDisconnect = "user_disconnect"
  case localCloseRequested = "local_close_requested"
  /// The endpoint withdraws: its holder turned remote access or remote use
  /// off, or quit the application (§4.5).
  case serviceWithdrawn = "service_withdrawn"
  case cardUnavailable = "card_unavailable"
  /// A frame failed authenticated decryption or framing.
  case sessionIntegrityFailed = "session_integrity_failed"
  case closeRequestedByPairing = "close_requested_by_pairing"
  case closeCompleteOrDeadline = "close_complete_or_deadline"
}

// swiftlint:enable sorted_enum_cases
