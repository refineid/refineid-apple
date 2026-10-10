// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The values fixed when the operation bodies were captured, recorded beside
/// them so the Swift engine builds from identical inputs.
internal struct OperationInputs: Decodable {
  private enum CodingKeys: String, CodingKey {
    case operationIdentifierRequest = "operation_id_request"
    case operationIdentifierReference = "operation_id_reference"
    case operationIdentifierStatus = "operation_id_status"
    case operationIdentifierError = "operation_id_error"
    case requestHashReference = "request_hash_reference"
    case requestHashStatus = "request_hash_status"
    case pairIdentifier = "pair_id"
    case sessionIdentifier = "session_id"
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
    case inspection = "inspection"
    case batchDocumentNames = "batch_document_names"
    case batchDigestsSha256 = "batch_digests_sha256"
    case batchSignatures = "batch_signatures"
  }

  internal let operationIdentifierRequest: String
  internal let operationIdentifierReference: String
  internal let operationIdentifierStatus: String
  internal let operationIdentifierError: String
  internal let requestHashReference: String
  internal let requestHashStatus: String
  internal let pairIdentifier: String
  internal let sessionIdentifier: String
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
  internal let inspection: OperationInspectionInput
  internal let batchDocumentNames: [String]
  internal let batchDigestsSha256: [String]
  internal let batchSignatures: [String]
}
