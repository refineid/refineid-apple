// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappTerminalReason {
  /// The reason a registered error name gives.
  internal init(_ error: ResultError) {
    switch error {
    case .busy:
      self = .busy

    case .duplicateOperation:
      self = .duplicateOperation

    case .invalidLifetime:
      self = .invalidLifetime

    case .operationExpired:
      self = .operationExpired

    case .unauthorized:
      self = .unauthorized

    case .unsupportedParameter:
      self = .unsupportedParameter

    case .userCancelled:
      self = .userCancelled

    case .retryFloor:
      self = .retryFloor

    case .cardError:
      self = .cardError

    case .operationFailed:
      self = .operationFailed
    }
  }
}
