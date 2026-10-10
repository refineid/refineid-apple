// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the specification registers them,
// so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// The `error` an `operation.result` names (RAPP v26.10.9 §8, §10).
internal enum ResultError: String, Equatable, CaseIterable {
  case userCancelled = "user_cancelled"
  case operationExpired = "operation_expired"
  case unauthorized = "unauthorized"
  case unsupportedParameter = "unsupported_parameter"
  case invalidCredential = "invalid_credential"
  case cardBlocked = "card_blocked"
  case cardError = "card_error"
  case operationFailed = "operation_failed"
  case duplicateOperation = "duplicate_operation"
  case userDeclined = "user_declined"
  case storageExhausted = "storage_exhausted"
  case operationAlreadyRetired = "operation_already_retired"
  /// A zero `expires_after_ms` (section 8.2.1).
  case invalidLifetime = "invalid_lifetime"
}

// swiftlint:enable sorted_enum_cases
