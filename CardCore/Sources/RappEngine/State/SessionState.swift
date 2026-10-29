// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Session component state (RAPP v26.10.29 formal state model).
///
/// A session instance exists per connection; `closed` is terminal for the
/// instance. Raw values are the formal model's names.
internal enum SessionState: String, CaseIterable, Sendable {
  case absent = "absent"
  /// Requester only.
  case connecting = "connecting"
  case authenticating = "authenticating"
  case healthy = "healthy"
  case closing = "closing"
  case closed = "closed"
}

// swiftlint:enable sorted_enum_cases
