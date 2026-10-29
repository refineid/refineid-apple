// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The answer a completed operation produced (RAPP v26.10.29 §9).
///
/// The certificates and signatures travel on to a verifier on the
/// requester; the engine consults none of their bytes.
public enum RappOperationResult: Equatable, Sendable {
  /// `read_certificate`: the DER certificate.
  case certificate(Data)
  /// `read_identity`.
  case identity(RappCardIdentity)
  /// `inspect_card`: the card's answer to reset, or its historical bytes;
  /// empty when the custodian's platform exposes neither.
  case inspection(answerToReset: Data)
  /// `browser_authenticate` or `sign_document`: the signature.
  case signature(Data)
  /// `batch_sign_documents`: the signatures, one per document, in order.
  case signatures([Data])
}
