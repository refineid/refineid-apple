// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Bounds the human-readable context an operation may carry.
internal enum OperationLimit {
  /// Longest display name or origin an authorizer is asked to render.
  internal static let displayContextBytes = 512
  /// Documents one `batch_sign_documents` may name (RAPP v26.10.1 §9.3).
  internal static let batchDocuments = 1...64
  /// Byte length of one batch document name (§9.3 `tstr .size (1..256)`).
  internal static let batchDocumentNameBytes = 1...256
}
