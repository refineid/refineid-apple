// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The error-envelope vocabulary this engine sends (RAPP v26.10.9 §10.4).
///
/// Semantic handling follows the name; the code is the informative number
/// the specification pairs with it.
internal enum EngineErrorName {
  internal static let unknownOperation = "unknown_operation"
  internal static let duplicateOperation = "duplicate_operation"
  internal static let operationFailed = "operation_failed"

  internal static let unknownOperationCode: UInt64 = 1_001
  internal static let duplicateOperationCode: UInt64 = 1_011
  internal static let operationFailedCode: UInt64 = 1_010
}
