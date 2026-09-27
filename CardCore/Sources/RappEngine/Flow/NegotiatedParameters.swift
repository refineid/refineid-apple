// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Parameter echo bound to the pairing channel.
///
/// Both peers send their own view; a difference means the two are not
/// answering the same offer over the same candidate.
internal struct NegotiatedParameters: Equatable {
  internal var offerHash: Data

  internal var transportProfile: String

  internal var candidateIdentifier: String

  internal var suite: String

  internal init(
    offerHash: Data,
    transportProfile: String,
    candidateIdentifier: String
  ) {
    self.init(
      offerHash: offerHash,
      transportProfile: transportProfile,
      candidateIdentifier: candidateIdentifier,
      suite: RappNoise.pairingSuite)
  }

  internal init(
    offerHash: Data,
    transportProfile: String,
    candidateIdentifier: String,
    suite: String
  ) {
    self.offerHash = offerHash
    self.transportProfile = transportProfile
    self.candidateIdentifier = candidateIdentifier
    self.suite = suite
  }

  internal static func from(map: [String: WireValue]) throws -> Self {
    var fields = map
    try requireVersion(&fields)
    try requireSuite(&fields, RappNoise.pairingSuite)
    let decodedOfferHash = try takeMessageBytes(&fields, "offer_hash")
    let decodedTransportProfile = try takeMessageText(&fields, "transport_profile")
    let decodedCandidateIdentifier = try takeMessageText(&fields, "candidate_id")
    guard fields.isEmpty else { throw MessageFieldError.invalidField("parameters") }
    try validateTransportName(decodedTransportProfile, "transport_profile")
    try validateLabel(decodedCandidateIdentifier, "candidate_id")
    return Self(
      offerHash: decodedOfferHash, transportProfile: decodedTransportProfile,
      candidateIdentifier: decodedCandidateIdentifier)
  }

  internal func asMap() throws -> [String: WireValue] {
    try validateTransportName(transportProfile, "transport_profile")
    try validateLabel(candidateIdentifier, "candidate_id")
    return [
      "version": wireVersionValue,
      "suite": .text(suite),
      "offer_hash": .bytes(offerHash),
      "transport_profile": .text(transportProfile),
      "candidate_id": .text(candidateIdentifier),
    ]
  }
}
