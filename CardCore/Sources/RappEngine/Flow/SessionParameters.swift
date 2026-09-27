// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Parameter echo bound to one session over a stored pairing.
internal struct SessionParameters: Equatable {
  internal var transportProfile: String

  internal var candidateIdentifier: String

  internal var grantsHash: Data

  internal var suite: String

  internal init(
    transportProfile: String,
    candidateIdentifier: String,
    grantsHash: Data
  ) {
    self.init(
      transportProfile: transportProfile,
      candidateIdentifier: candidateIdentifier,
      grantsHash: grantsHash,
      suite: RappNoise.sessionSuite)
  }

  internal init(
    transportProfile: String,
    candidateIdentifier: String,
    grantsHash: Data,
    suite: String
  ) {
    self.transportProfile = transportProfile
    self.candidateIdentifier = candidateIdentifier
    self.grantsHash = grantsHash
    self.suite = suite
  }

  internal static func from(map: [String: WireValue]) throws -> Self {
    var fields = map
    try requireVersion(&fields)
    let decodedSuite = try takeMessageText(&fields, "suite")
    guard decodedSuite == RappNoise.sessionSuite else {
      throw MessageFieldError.invalidField("suite")
    }
    let decodedTransportProfile = try takeMessageText(&fields, "transport_profile")
    let decodedCandidateIdentifier = try takeMessageText(&fields, "candidate_id")
    let decodedGrantsHash = try takeMessageBytes(&fields, "grants_hash")
    guard fields.isEmpty, decodedGrantsHash.count == PairRecordSize.grantsHash else {
      throw MessageFieldError.invalidField("parameters")
    }
    try validateTransportName(decodedTransportProfile, "transport_profile")
    try validateLabel(decodedCandidateIdentifier, "candidate_id")
    return Self(
      transportProfile: decodedTransportProfile,
      candidateIdentifier: decodedCandidateIdentifier,
      grantsHash: decodedGrantsHash,
      suite: decodedSuite)
  }

  internal func asMap() throws -> [String: WireValue] {
    try validateTransportName(transportProfile, "transport_profile")
    try validateLabel(candidateIdentifier, "candidate_id")
    return [
      "version": wireVersionValue,
      "suite": .text(suite),
      "transport_profile": .text(transportProfile),
      "candidate_id": .text(candidateIdentifier),
      "grants_hash": .bytes(grantsHash),
    ]
  }
}
