// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored revocation corpus (RAPP v26.10.18 §4.6).
internal struct RevocationCorpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case announcementSelection = "announcement_selection"
    case malformedRecord = "malformed_record"
    case protocolDocumentVersion = "protocol_document_version"
    case retentionWindow = "retention_window"
    case revocationAcceptance = "revocation_acceptance"
    case revocationHint = "revocation_hint"
    case revocationKey = "revocation_key"
    case sessionRecord = "session_record"
  }

  internal let protocolDocumentVersion: String
  internal let revocationKey: [RevocationKeyVector]
  internal let revocationHint: [RevocationHintVector]
  internal let revocationAcceptance: [RevocationAcceptanceVector]
  internal let sessionRecord: [RevokedSessionRecordVector]
  internal let malformedRecord: [RevokedSessionRecordVector]
  internal let retentionWindow: [RetentionWindowVector]
  internal let announcementSelection: [RevocationSelectionVector]
}
