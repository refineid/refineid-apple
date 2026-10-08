// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are ordered as the operation proceeds, so the source reads in
// the order the stages can occur.
// swiftlint:disable sorted_enum_cases

import Foundation

/// The phase an authorization has reached.
internal enum AuthorizationStage: Equatable {
  case requested
  case awaitingConsent
  case executingSafeRead
  case executing
  case resultPending
  case terminal
}

// swiftlint:enable sorted_enum_cases
