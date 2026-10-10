// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.10 §2.2.1 and §4.3).

/// The vendored withdrawal corpus (RAPP v26.10.10 §4.5).
internal struct WithdrawalCorpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case announcementSelection = "announcement_selection"
    case malformedRecord = "malformed_record"
    case protocolDocumentVersion = "protocol_document_version"
    case sessionClose = "session_close"
    case withdrawalAcceptance = "withdrawal_acceptance"
    case withdrawalHint = "withdrawal_hint"
    case withdrawalKey = "withdrawal_key"
    case withdrawnRecord = "withdrawn_record"
  }

  internal let protocolDocumentVersion: String
  internal let withdrawalKey: [WithdrawalKeyVector]
  internal let withdrawalHint: [WithdrawalHintVector]
  internal let withdrawalAcceptance: [WithdrawalAcceptanceVector]
  internal let withdrawnRecord: [WithdrawnRecordVector]
  internal let malformedRecord: [RecordVector]
  internal let sessionClose: [SessionCloseVector]
  internal let announcementSelection: [SelectionVector]
}
