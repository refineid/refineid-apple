// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappModelTables {
  /// Operation component rules.
  internal static let operation: [RappRule<OperationState, OperationEvent>] = [
    RappRule(
      from: .idle,
      event: .requestReceived,
      role: .custodian,
      destination: .requested,
      actions: [.startExpiryClock]
    ),
    RappRule(
      from: .idle,
      event: .requestDuplicate,
      role: .custodian,
      destination: .idle,
      actions: [.sendErrorDuplicateOperation]
    ),
    RappRule(
      from: .idle,
      event: .requestWhileBusy,
      role: .custodian,
      destination: .idle,
      actions: [.sendErrorBusy]
    ),
    RappRule(
      from: .idle,
      event: .requestUnauthorized,
      role: .custodian,
      destination: .rejected,
      actions: [.sendResultUnauthorized]
    ),
    RappRule(
      from: .idle,
      event: .requestUnsupported,
      role: .custodian,
      destination: .rejected,
      actions: [.sendResultUnsupportedParameter]
    ),
    RappRule(
      from: .requested,
      event: .cardHeldElsewhere,
      role: .custodian,
      destination: .queued,
      actions: [.sendProgressQueued]
    ),
    RappRule(
      from: [.requested, .queued],
      event: .cardAcquiredForConsent,
      role: .custodian,
      destination: .awaitingConsent,
      actions: [.presentConsent, .sendProgressConsentShown]
    ),
    RappRule(
      from: [.requested, .queued],
      event: .cardAcquiredForRead,
      role: .custodian,
      destination: .executing,
      actions: [.executeRead]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .userDenied,
      role: .custodian,
      destination: .rejected,
      actions: [.dismissConsent, .sendResultUserCancelled, .releaseCard]
    ),
    RappRule(
      from: .awaitingConsent,
      event: .userApproved,
      role: .custodian,
      destination: .executing,
      actions: [.dismissConsent, .checkRetryFloor, .consumeCardCommand]
    ),
    RappRule(
      from: .executing,
      event: .waitingForCard,
      role: .custodian,
      destination: .executing,
      actions: [.sendProgressWaitingForCard]
    ),
    RappRule(
      from: .executing,
      event: .cardFound,
      role: .custodian,
      destination: .executing,
      actions: [.sendProgressCardWaitEnded]
    ),
    RappRule(
      from: .executing,
      event: .wrongPin,
      role: .custodian,
      destination: .executing,
      actions: [.promptPinAgain]
    ),
    RappRule(
      from: .executing,
      event: .retryFloorRefused,
      role: .custodian,
      destination: .rejected,
      actions: [.clearOperationCredentials, .sendResultRetryFloor, .releaseCard]
    ),
    RappRule(
      from: .executing,
      event: .cardSuccess,
      role: .custodian,
      destination: .completed,
      actions: [.clearOperationCredentials, .sendResultCompleted, .releaseCard]
    ),
    RappRule(
      from: .executing,
      event: .cardError,
      role: .custodian,
      destination: .rejected,
      actions: [.clearOperationCredentials, .sendResultCardError, .releaseCard]
    ),
    RappRule(
      from: [.requested, .queued, .awaitingConsent],
      event: .requestExpired,
      role: .custodian,
      destination: .cancelled,
      actions: [.dismissConsent, .sendResultOperationExpired, .releaseCard]
    ),
    RappRule(
      from: [.requested, .queued, .awaitingConsent],
      event: .sessionClosed,
      role: .custodian,
      destination: .idle,
      actions: [.dismissConsent, .clearOperationCredentials, .releaseCard]
    ),
    RappRule(
      from: .executing,
      event: .sessionClosed,
      role: .custodian,
      destination: .idle,
      actions: [
        .continueCardExchangeLocally, .discardAnswer, .clearOperationCredentials, .releaseCard,
      ]
    ),
    RappRule(
      from: .idle,
      event: .requestSent,
      role: .requester,
      destination: .requested,
      actions: []
    ),
    RappRule(
      from: .requested,
      event: .progressReceived,
      role: .requester,
      destination: .requested,
      actions: [.showProgress]
    ),
    RappRule(
      from: .requested,
      event: .resultCompletedReceived,
      role: .requester,
      destination: .completed,
      actions: [.releaseResult]
    ),
    RappRule(
      from: .requested,
      event: .resultRejectedReceived,
      role: .requester,
      destination: .rejected,
      actions: [.releaseFailure]
    ),
    RappRule(
      from: .requested,
      event: .resultCancelledReceived,
      role: .requester,
      destination: .cancelled,
      actions: [.releaseFailure]
    ),
    RappRule(
      from: .requested,
      event: .sessionClosed,
      role: .requester,
      destination: .idle,
      actions: [.reportOperationLost]
    ),
  ]
}
