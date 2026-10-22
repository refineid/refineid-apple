// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Operation component event.
///
/// Raw values are the formal model's event names, so a Swift case and a model
/// rule are compared without a translation table.
internal enum OperationEvent: String, CaseIterable, Sendable {
  /// Identifier unseen, no live operation, profile granted.
  case requestReceived = "request_received"
  case requestDuplicate = "request_duplicate"
  case requestWhileBusy = "request_while_busy"
  case requestUnauthorized = "request_unauthorized"
  case requestUnsupported = "request_unsupported"
  case cardHeldElsewhere = "card_held_elsewhere"
  case cardAcquiredForConsent = "card_acquired_for_consent"
  case cardAcquiredForRead = "card_acquired_for_read"
  case userDenied = "user_denied"
  case userApproved = "user_approved"
  case waitingForCard = "waiting_for_card"
  case cardFound = "card_found"
  case wrongPin = "wrong_pin"
  case retryFloorRefused = "retry_floor_refused"
  case cardSuccess = "card_success"
  case cardError = "card_error"
  case requestExpired = "request_expired"
  case sessionClosed = "session_closed"
  case requestSent = "request_sent"
  case progressReceived = "progress_received"
  case resultCompletedReceived = "result_completed_received"
  /// An `operation.result` rejected, or an `error` busy or
  /// `duplicate_operation`.
  case resultRejectedReceived = "result_rejected_received"
  case resultCancelledReceived = "result_cancelled_received"
}

// swiftlint:enable sorted_enum_cases
