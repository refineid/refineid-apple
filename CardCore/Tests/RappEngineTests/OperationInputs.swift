// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The values the operation bodies were encoded from, recorded beside them
/// so the Swift engine builds from identical inputs.
internal struct OperationInputs: Decodable {
  private enum CodingKeys: String, CodingKey {
    case operationIdentifierRequest = "operation_id_request"
    case operationIdentifierResult = "operation_id_result"
    case operationIdentifierError = "operation_id_error"
    case pairIdentifier = "pair_id"
    case digestSha256 = "digest_sha256"
    case digestSha384 = "digest_sha384"
    case signatureBytes = "signature_bytes"
    case certificateDer = "certificate_der"
    case answerToReset = "atr"
    case origin = "origin"
    case documentName = "document_name"
    case holderName = "holder_name"
    case cardIdentifier = "card_id"
    case issuanceDate = "issuance_date"
    case expirationDate = "expiration_date"
    case localStartMilliseconds = "local_start_ms"
    case expiresAfterMilliseconds = "expires_after_ms"
    case batchDocumentNames = "batch_document_names"
    case batchDigestsSha256 = "batch_digests_sha256"
    case batchSignatures = "batch_signatures"
    case errorMessages = "error_messages"
  }

  internal let operationIdentifierRequest: String
  internal let operationIdentifierResult: String
  internal let operationIdentifierError: String
  internal let pairIdentifier: String
  internal let digestSha256: String
  internal let digestSha384: String
  internal let signatureBytes: String
  internal let certificateDer: String
  internal let answerToReset: String
  internal let origin: String
  internal let documentName: String
  internal let holderName: String
  internal let cardIdentifier: String
  internal let issuanceDate: String
  internal let expirationDate: String
  internal let localStartMilliseconds: UInt64
  internal let expiresAfterMilliseconds: UInt64
  internal let batchDocumentNames: [String]
  internal let batchDigestsSha256: [String]
  internal let batchSignatures: [String]
  /// The `message` each error body carries, by error name.
  internal let errorMessages: [String: String]
}
