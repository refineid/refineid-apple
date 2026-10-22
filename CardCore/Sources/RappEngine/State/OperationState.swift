// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Operation component state (RAPP v26.10.22 formal state model).
///
/// An operation instance exists per operation identifier within one session;
/// `none` is the absence of one, and also where an operation goes when its
/// session ends. Raw values are the formal model's names.
internal enum OperationState: String, CaseIterable, Sendable {
  case idle = "none"
  case requested = "requested"
  /// Custodian only.
  case queued = "queued"
  /// Custodian only.
  case awaitingConsent = "awaiting_consent"
  case executing = "executing"
  case completed = "completed"
  case rejected = "rejected"
  case cancelled = "cancelled"
}

// swiftlint:enable sorted_enum_cases
