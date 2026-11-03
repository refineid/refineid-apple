// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored operation-protocol message bodies (RAPP v26.11.2 §7.1, §9,
/// §10.3).
internal struct OperationCorpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case format = "format"
    case protocolDocumentVersion = "protocol_document_version"
    case fixedInputs = "fixed_inputs"
    case vectors = "vectors"
    case rejected = "rejected"
    case refused = "refused"
    case rejectedByFrameBound = "rejected_by_frame_bound"
  }

  internal let format: String
  internal let protocolDocumentVersion: String
  internal let fixedInputs: OperationInputs
  internal let vectors: [OperationVector]
  /// Bodies a receiver must refuse.
  internal let rejected: [OperationVector]
  /// Requests that decode and are refused with `unsupported_parameter`.
  internal let refused: [OperationVector]
  /// Packages whose request does not fit one frame (RAPP v26.11.2 §9.3).
  internal let rejectedByFrameBound: [FrameBoundVector]
}
