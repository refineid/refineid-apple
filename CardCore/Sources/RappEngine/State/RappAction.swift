// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// A protocol effect a transition emits.
///
/// Actions are data. A transition returns the ordered list an adapter must
/// execute; nothing here performs the effect. Raw values are the formal
/// model's action names, and the model carries each one's prose definition.
internal enum RappAction: String, CaseIterable, Sendable {
  // Offer and pairing handshake.
  case generateOfferId = "generate_offer_id"
  case generatePairingSecret = "generate_pairing_secret"
  case startOfferExpiry = "start_offer_expiry"
  case displayPairingCode = "display_pairing_code"
  case hidePairingCode = "hide_pairing_code"
  case selectOneCandidate = "select_one_candidate"
  case connectCandidate = "connect_candidate"
  case preparePairingResponder = "prepare_pairing_responder"
  case beginPairingHandshakeInitiator = "begin_pairing_handshake_initiator"
  case deriveChannelIdentifiers = "derive_channel_identifiers"
  case destroyPairingSecret = "destroy_pairing_secret"
  case stopAcceptingCandidates = "stop_accepting_candidates"
  case sendPairingHello = "send_pairing_hello"
  case showPeerAndRequestedGrants = "show_peer_and_requested_grants"
  case discardCandidate = "discard_candidate"
  case retainOffer = "retain_offer"
  case invalidateOffer = "invalidate_offer"
  case closeCandidate = "close_candidate"
  case storePairRecordAtomically = "store_pair_record_atomically"
  case closePairingChannel = "close_pairing_channel"
  case sendPairingAbortBestEffort = "send_pairing_abort_best_effort"
  case destroyCandidateKeys = "destroy_candidate_keys"

  // Visible security state.
  case showConnected = "show_connected"
  case showPairedDisconnected = "show_paired_disconnected"
  case showChecking = "show_checking"
  case showDisconnecting = "show_disconnecting"
  case showConnectionStopped = "show_connection_stopped"
  case showRevoked = "show_revoked"

  // Pairing termination.
  case closeSession = "close_session"
  case destroyPairKeys = "destroy_pair_keys"
  case destroyRelayTokens = "destroy_relay_tokens"
  case clearPairMetadata = "clear_pair_metadata"
  case clearResidualPairRecord = "clear_residual_pair_record"
  case recordPeerInitiated = "record_peer_initiated"
  case sendCloseBestEffort = "send_close_best_effort"

  // Session establishment.
  case selectOneTransport = "select_one_transport"
  case openTransport = "open_transport"
  case associatePairingFromRendezvous = "associate_pairing_from_rendezvous"
  case beginKkInitiator = "begin_kk_initiator"
  case beginKkResponder = "begin_kk_responder"
  case deriveSessionIdentifiers = "derive_session_identifiers"
  case sendSessionReady = "send_session_ready"
  case sendErrorBusy = "send_error_busy"

  // Liveness and session teardown.
  case startAuthenticatedLiveness = "start_authenticated_liveness"
  case blockNewOperations = "block_new_operations"
  case startBackoffAndDeadline = "start_backoff_and_deadline"
  case resetBackoff = "reset_backoff"
  case recordPeerCloseReason = "record_peer_close_reason"
  case countCandidateFailureHint = "count_candidate_failure_hint"
  case noteCloseNoticeImpossible = "note_close_notice_impossible"
  case proceedWithoutCloseNotice = "proceed_without_close_notice"
  case abortCandidate = "abort_candidate"
  case destroySessionMaterial = "destroy_session_material"
  case destroyCredentialBuffers = "destroy_credential_buffers"
  case persistTerminalSessionRecord = "persist_terminal_session_record"

  // Operation admission and consent.
  case validateSchemaHashExpiryAndContext = "validate_schema_hash_expiry_and_context"
  case startExpiryClock = "start_expiry_clock"
  case beginSafePrerequisiteReads = "begin_safe_prerequisite_reads"
  case presentConsentPerProfile = "present_consent_per_profile"
  case dismissConsent = "dismiss_consent"
  case clearOperationCredentials = "clear_operation_credentials"
  case clearAllActiveCredentials = "clear_all_active_credentials"
  case removeRejectedCredentialAndDerivedState = "remove_rejected_credential_and_derived_state"

  // Proxy result messages.
  case sendPrepared = "send_prepared"
  case sendResultCompleted = "send_result_completed"
  case sendResultDenied = "send_result_denied"
  case sendResultCancelled = "send_result_cancelled"
  case sendResultRejected = "send_result_rejected"
  case sendResultRetryPolicyRefused = "send_result_retry_policy_refused"
  case sendResultCredentialRejectedBestEffort = "send_result_credential_rejected_best_effort"
  case sendResultAmbiguousBestEffort = "send_result_ambiguous_best_effort"

  // Cross-component requests.
  case requestSessionClose = "request_session_close"
  case requestSessionCloseCredentialRejected = "request_session_close_credential_rejected"
  case revokePairAfterCredentialRejection = "revoke_pair_after_credential_rejection"
  case requestSessionCloseAmbiguous = "request_session_close_ambiguous"
  case sendOperationCancel = "send_operation_cancel"
  case sendOperationProgress = "send_operation_progress"

  // The commit point and the single card transmission.
  case durablyWriteCommitBeforeTransmission = "durably_write_commit_before_transmission"
  case consumeNonClonableCommand = "consume_non_clonable_command"
  case incrementTransmissionCountOnce = "increment_transmission_count_once"
  case recordAdvisoryCancel = "record_advisory_cancel"
  case continueCardExchangeLocally = "continue_card_exchange_locally"
  case noteResultDeliveryImpossible = "note_result_delivery_impossible"

  // Proxy journal.
  case persistResult = "persist_result"
  case persistRejection = "persist_rejection"
  case persistCancelled = "persist_cancelled"
  case persistAmbiguous = "persist_ambiguous"
  case persistCompleted = "persist_completed"
  case persistDeliveryUncertain = "persist_delivery_uncertain"
  case retainResultUnderLocalStorage = "retain_result_under_local_storage"
  case releaseResult = "release_result"
  case prohibitRetry = "prohibit_retry"
  case prohibitCardRetry = "prohibit_card_retry"

  // Requester journal.
  case computeRequestHash = "compute_request_hash"
  case journalRequest = "journal_request"
  case journalPrepared = "journal_prepared"
  case journalCommitIntentDurably = "journal_commit_intent_durably"
  case journalCompleted = "journal_completed"
  case journalDenied = "journal_denied"
  case journalCancelled = "journal_cancelled"
  case journalRejected = "journal_rejected"
  case journalCredentialRejected = "journal_credential_rejected"
  case journalAmbiguous = "journal_ambiguous"
  case sendResultAck = "send_result_ack"
}

// swiftlint:enable sorted_enum_cases
