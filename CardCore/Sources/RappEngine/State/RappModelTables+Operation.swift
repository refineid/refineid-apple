// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappModelTables {
  /// Operation component rules.
  ///
  /// Messages naming an unknown or terminal operation are stale-reference
  /// races and appear in no rule; they transition nothing.
  internal static let operation: [RappRule<OperationState, OperationEvent>] = [
    RappRule(
      from: .idle,
      event: .requestSent,
      role: .requester,
      condition: .admissionPermitted,
      destination: .requested,
      actions: [.computeRequestHash, .journalRequest, .startExpiryClock]
    ),
    RappRule(
      from: .idle,
      event: .requestReceived,
      role: .proxy,
      condition: .admissionPermitted,
      destination: .requested,
      actions: [.validateSchemaHashExpiryAndContext, .startExpiryClock]
    ),
    RappRule(
      from: .requested,
      event: .requestValid,
      role: .proxy,
      destination: .awaitingConsent,
      actions: [.beginSafePrerequisiteReads, .presentConsentPerProfile]
    ),
    RappRule(
      from: .requested,
      event: .requestInvalidOrUnsupported,
      role: .proxy,
      destination: .rejected,
      actions: [.sendResultRejected]
    ),
    RappRule(
      from: [.requested, .awaitingConsent],
      event: .cancelReceived,
      role: .proxy,
      destination: .cancelled,
      actions: [.clearOperationCredentials, .dismissConsent, .sendResultCancelled]
    ),
    RappRule(
      from: [.requested, .awaitingConsent],
      event: .requestExpired,
      role: .proxy,
      destination: .cancelled,
      actions: [.clearOperationCredentials, .dismissConsent, .sendResultCancelled]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .userDenied,
      role: .proxy,
      destination: .denied,
      actions: [.clearOperationCredentials, .sendResultDenied]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .retryPolicyRefused,
      role: .proxy,
      destination: .rejected,
      actions: [
        .clearOperationCredentials, .sendResultRetryPolicyRefused, .requestSessionClose,
      ]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .invalidCanOrPin1OrPin2,
      role: .proxy,
      destination: .credentialRejected,
      actions: [
        .clearAllActiveCredentials, .removeRejectedCredentialAndDerivedState,
        .sendResultCredentialRejectedBestEffort, .revokePairAfterCredentialRejection,
        .requestSessionCloseCredentialRejected,
      ]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .safeReadsComplete,
      role: .proxy,
      condition: .profileHasNoConsequentialCommand,
      destination: .resultPending,
      actions: [.persistResult, .sendResultCompleted]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .userApprovedAndProxyReady,
      role: .proxy,
      condition: .zeroTransmissions,
      destination: .prepared,
      actions: [.sendPrepared]
    ),
    RappRule(
      from: .prepared,
      event: .cancelReceived,
      role: .proxy,
      destination: .cancelled,
      actions: [.clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: .prepared,
      event: .requestExpired,
      role: .proxy,
      destination: .cancelled,
      actions: [.clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: .prepared,
      event: .validCommit,
      role: .proxy,
      condition: .hashMatches,
      destination: .committed,
      actions: [.durablyWriteCommitBeforeTransmission]
    ),
    RappRule(
      from: .committed,
      event: .beginCardCommand,
      role: .proxy,
      condition: .zeroTransmissions,
      destination: .executing,
      actions: [.consumeNonClonableCommand, .incrementTransmissionCountOnce]
    ),
    RappRule(
      from: .committed,
      event: .cancelReceived,
      role: .proxy,
      condition: .provenNoTransmission,
      destination: .cancelled,
      actions: [.persistCancelled, .clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: [.committed, .executing],
      event: .crashRecoveredWithoutTerminalResult,
      role: .both,
      destination: .ambiguous,
      actions: [.persistAmbiguous, .prohibitRetry]
    ),
    RappRule(
      from: .executing,
      event: .cardSuccess,
      role: .proxy,
      destination: .resultPending,
      actions: [.persistResult, .clearOperationCredentials, .sendResultCompleted]
    ),
    RappRule(
      from: .executing,
      event: .invalidCanOrPin1OrPin2,
      role: .proxy,
      destination: .credentialRejected,
      actions: [
        .clearAllActiveCredentials, .removeRejectedCredentialAndDerivedState,
        .sendResultCredentialRejectedBestEffort, .revokePairAfterCredentialRejection,
        .requestSessionCloseCredentialRejected,
      ]
    ),
    RappRule(
      from: .executing,
      event: .cardPolicyRejection,
      role: .proxy,
      destination: .rejected,
      actions: [.clearOperationCredentials, .persistRejection, .sendResultRejected]
    ),
    RappRule(
      from: .executing,
      event: .cardRemovedBeforeTransmit,
      role: .proxy,
      condition: .provenNoTransmission,
      destination: .cancelled,
      actions: [.persistCancelled, .clearOperationCredentials, .sendResultCancelled]
    ),
    RappRule(
      from: .executing,
      event: .cardRemovedOrTransportUncertain,
      role: .proxy,
      destination: .ambiguous,
      actions: [
        .clearOperationCredentials, .persistAmbiguous, .prohibitRetry,
        .sendResultAmbiguousBestEffort, .requestSessionCloseAmbiguous,
      ]
    ),
    RappRule(
      from: .executing,
      event: .cancelReceived,
      role: .proxy,
      destination: .executing,
      actions: [.recordAdvisoryCancel]
    ),
    RappRule(
      from: .executing,
      event: .sessionClosedPostCommit,
      role: .proxy,
      destination: .executing,
      actions: [.continueCardExchangeLocally, .noteResultDeliveryImpossible]
    ),
    RappRule(
      from: .resultPending,
      event: .validResultAck,
      role: .proxy,
      destination: .completed,
      actions: [.persistCompleted, .releaseResult]
    ),
    RappRule(
      from: .resultPending,
      event: .sessionClosedBeforeAck,
      role: .proxy,
      destination: .deliveryUncertain,
      actions: [.persistDeliveryUncertain, .prohibitCardRetry, .retainResultUnderLocalStorage]
    ),
    RappRule(
      from: .committed,
      event: .sessionClosedPostCommit,
      role: .proxy,
      destination: .cancelled,
      actions: [.persistCancelled, .clearOperationCredentials]
    ),
    RappRule(
      from: .requested,
      event: .preparedReceived,
      role: .requester,
      condition: .hashEchoMatches,
      destination: .prepared,
      actions: [.journalPrepared]
    ),
    RappRule(
      from: [.requested, .prepared],
      event: .cancelSentOrRequestExpired,
      role: .requester,
      destination: .cancelled,
      actions: [.sendOperationCancel, .journalCancelled]
    ),
    RappRule(
      from: .prepared,
      event: .commitSent,
      role: .requester,
      destination: .committed,
      actions: [.journalCommitIntentDurably]
    ),
    RappRule(
      from: .requested,
      event: .resultCompletedReceived,
      role: .requester,
      condition: .profileHasNoConsequentialCommand,
      destination: .completed,
      actions: [.retainResultUnderLocalStorage, .sendResultAck, .journalCompleted]
    ),
    RappRule(
      from: [.requested, .prepared],
      event: .resultDeniedReceived,
      role: .requester,
      destination: .denied,
      actions: [.journalDenied, .sendResultAck]
    ),
    RappRule(
      from: [.requested, .prepared, .committed],
      event: .resultCancelledReceived,
      role: .requester,
      destination: .cancelled,
      actions: [.journalCancelled, .sendResultAck]
    ),
    RappRule(
      from: [.requested, .prepared, .committed],
      event: .resultRejectedReceived,
      role: .requester,
      destination: .rejected,
      actions: [.journalRejected, .sendResultAck]
    ),
    RappRule(
      from: [.requested, .prepared, .committed],
      event: .resultCredentialRejectedReceived,
      role: .requester,
      destination: .credentialRejected,
      actions: [.journalCredentialRejected, .sendResultAck, .revokePairAfterCredentialRejection]
    ),
    RappRule(
      from: .committed,
      event: .resultCompletedReceived,
      role: .requester,
      destination: .completed,
      actions: [.retainResultUnderLocalStorage, .sendResultAck, .journalCompleted]
    ),
    RappRule(
      from: .committed,
      event: .resultAmbiguousReceived,
      role: .requester,
      destination: .ambiguous,
      actions: [.journalAmbiguous, .sendResultAck, .prohibitRetry]
    ),
    RappRule(
      from: .committed,
      event: .sessionClosedPostCommit,
      role: .requester,
      destination: .ambiguous,
      actions: [.journalAmbiguous, .prohibitRetry]
    ),
    RappRule(
      from: [.requested, .awaitingConsent, .prepared],
      event: .sessionClosedPreCommit,
      role: .both,
      destination: .cancelled,
      actions: [.clearOperationCredentials, .persistCancelled]
    ),
  ]
}
