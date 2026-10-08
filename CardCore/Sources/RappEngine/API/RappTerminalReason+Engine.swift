// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappTerminalReason {
  /// The reason a received failure result names (RAPP v26.10.1 §10).
  internal init(status: ResultStatus, error: ResultError?) {
    switch (status, error) {
    case (.ambiguous, _):
      self = .cardCompletionAmbiguous

    case (.credentialRejected, _):
      self = .credentialRejected

    case (.cancelled, .some(.cardError)):
      self = .cardRemovedBeforeTransmit

    case (.cancelled, _):
      self = .requestExpired

    case (_, .some(.userCancelled)), (_, .some(.userDeclined)):
      self = .userDenied

    case (_, .some(.invalidCredential)):
      self = .invalidCredential

    case (_, .some(.operationFailed)), (_, .some(.storageExhausted)):
      // The custodian declined to proceed with the card, as its retry
      // floor or its storage requires.
      self = .retryPolicyRefused

    default:
      self = .requestInvalidOrUnsupported
    }
  }

  /// The reason a local custodian failure reports.
  internal init(_ failure: ProxyFailure) {
    self.init(status: failure.status, error: failure.error)
  }
}
