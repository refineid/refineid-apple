// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ResultError {
  /// A received name, with an unrecognized one handled as a general
  /// `operation_failed` (section 10.4).
  internal init(wireName: String) {
    self = Self(rawValue: wireName) ?? .operationFailed
  }

  /// Whether a result may pair this error with `status`.
  internal func permits(_ status: ResultStatus) -> Bool {
    switch self {
    case .operationExpired:
      status == .cancelled

    case .cardBlocked:
      status == .credentialRejected

    case .cardError:
      status == .cancelled || status == .ambiguous

    case .operationAlreadyRetired:
      status == .completed

    case .userCancelled, .unauthorized, .unsupportedParameter, .invalidCredential,
      .operationFailed, .duplicateOperation, .userDeclined, .storageExhausted, .invalidLifetime:
      status == .rejected
    }
  }
}
