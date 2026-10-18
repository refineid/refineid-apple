// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// How an operation ended without an answer: the result's status and
/// error, and the signatures an interrupted batch made before it.
///
/// The journaled state follows from the status (``ResultStatus/failureState``).
internal struct TerminalOutcome: Equatable {
  internal let status: ResultStatus
  internal let error: ResultError?
  internal let batchSignatures: [Data]
}
