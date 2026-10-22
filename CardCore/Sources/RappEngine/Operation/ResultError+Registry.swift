// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ResultError {
  /// Whether an `operation.result` may pair this error with `status`.
  ///
  /// `busy` and `duplicate_operation` refuse a request before admission and
  /// travel only as an `error` message (RAPP v26.10.22 §8.1 item 1);
  /// `operation_expired` cancels (§8.1 item 2); every other name rejects.
  internal func permits(_ status: ResultStatus) -> Bool {
    switch self {
    case .busy, .duplicateOperation:
      false

    case .operationExpired:
      status == .cancelled

    case .invalidLifetime, .unauthorized, .unsupportedParameter, .userCancelled, .retryFloor,
      .cardError, .operationFailed:
      status == .rejected
    }
  }
}
