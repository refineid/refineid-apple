// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the specification registers them,
// so the source reads line for line against the document.
// swiftlint:disable sorted_enum_cases

import Foundation

/// Typed output of one completed card operation.
internal enum CardOperationResult: Equatable {
  /// The answer to reset, or its historical bytes; empty when the
  /// custodian's platform exposes neither.
  case inspection(answerToReset: Data)
  case identity(CardIdentity)
  case certificate(Data)
  case signature(Data)
  /// The ordered signatures of a completed `batch_sign_documents`.
  case signatures([Data])
}

// swiftlint:enable sorted_enum_cases
