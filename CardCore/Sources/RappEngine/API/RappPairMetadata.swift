// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a stored pairing says about itself, without its keys.
public struct RappPairMetadata: Equatable, Sendable {
  /// The identifier the pairing is stored under.
  public var pairId: Data
  /// Which side of the pairing this endpoint is.
  public var role: RappEndpointRole
  /// The credential profiles both endpoints granted.
  public var profiles: [String]
  /// The transport profile the pairing is bound to.
  public var transportProfile: String
  /// The transport candidate the pairing is bound to.
  public var candidateId: String
  /// When the pairing was created.
  public var createdAtMs: UInt64
  /// Whether both endpoints confirmed storing the pairing (RAPP v26.10.18
  /// §4.3 item 4); an unconfirmed record is revoked, never used.
  public var storageConfirmed: Bool

  /// Describes a stored pairing.
  public init(
    pairId: Data,
    role: RappEndpointRole,
    profiles: [String],
    transportProfile: String,
    candidateId: String,
    createdAtMs: UInt64,
    storageConfirmed: Bool
  ) {
    self.pairId = pairId
    self.role = role
    self.profiles = profiles
    self.transportProfile = transportProfile
    self.candidateId = candidateId
    self.createdAtMs = createdAtMs
    self.storageConfirmed = storageConfirmed
  }
}
