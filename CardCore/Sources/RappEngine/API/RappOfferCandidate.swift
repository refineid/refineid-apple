// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One transport a scanned offer advertises.
public struct RappOfferCandidate: Equatable, Sendable {
  /// The transport profile this candidate implements.
  public var profile: String
  /// The identifier naming this candidate within the offer.
  public var candidateId: String

  /// Describes one advertised transport.
  public init(profile: String, candidateId: String) {
    self.profile = profile
    self.candidateId = candidateId
  }
}
