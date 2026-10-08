// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A refused authorization step.
internal enum AuthorizationError: Error, Equatable {
  case approvalMismatch
  case expired
  case invalidResult
  case journal(JournalError)
  case referenceMismatch
  case wrongStage(stage: AuthorizationStage)
}
