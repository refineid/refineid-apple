// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the specification registers them,
// so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// `operation-status-val` (RAPP v26.10.9 §7.1).
internal enum ResultStatus: String, Equatable {
  case completed = "completed"
  case rejected = "rejected"
  case credentialRejected = "credential_rejected"
  case cancelled = "cancelled"
  case ambiguous = "ambiguous"
}

// swiftlint:enable sorted_enum_cases
