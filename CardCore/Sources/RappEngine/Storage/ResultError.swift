// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the specification's table lists
// them, so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// The registered error names of an `error` message and of the `error`
/// field of `operation.result` (RAPP v26.10.21 §10.3).
internal enum ResultError: String, Equatable, CaseIterable {
  case busy = "busy"
  case duplicateOperation = "duplicate_operation"
  case invalidLifetime = "invalid_lifetime"
  case operationExpired = "operation_expired"
  case unauthorized = "unauthorized"
  case unsupportedParameter = "unsupported_parameter"
  case userCancelled = "user_cancelled"
  case retryFloor = "retry_floor"
  case cardError = "card_error"
  case operationFailed = "operation_failed"
}

// swiftlint:enable sorted_enum_cases
