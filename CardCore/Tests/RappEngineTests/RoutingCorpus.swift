// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.10 §2.2.1 and §4.3).

internal struct RoutingCorpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case announcementSelection = "announcement_selection"
    case discoveryAcceptance = "discovery_acceptance"
    case discoveryHint = "discovery_hint"
    case discoveryRecord = "discovery_record"
    case pairKeys = "pair_keys"
    case protocolDocumentVersion = "protocol_document_version"
    case routingLookup = "routing_lookup"
    case routingPreamble = "routing_preamble"
    case routingTag = "routing_tag"
  }

  internal let protocolDocumentVersion: String
  internal let pairKeys: [PairKeysVector]
  internal let discoveryHint: [DiscoveryHintVector]
  internal let discoveryAcceptance: [DiscoveryAcceptanceVector]
  internal let routingTag: [RoutingTagVector]
  internal let routingPreamble: [RoutingPreambleVector]
  internal let routingLookup: [RoutingLookupVector]
  internal let discoveryRecord: [RecordVector]
  internal let announcementSelection: [SelectionVector]
}
