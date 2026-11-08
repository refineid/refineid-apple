// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which advertisers a requester's link dials, by the identifiers Core
/// Bluetooth assigns them on this device (STPA CC-53).
///
/// Every RAPP custodian advertises the same service UUID and nothing that
/// names a pairing (RAPP v26.11.8 §4.1), so the requester learns which
/// advertiser is its phone only by routing a preamble to it.
public struct RappBleCentralPeers: Sendable, Equatable {
  /// The advertiser that last routed this pairing's preamble; dialed at
  /// once while it advertises.
  public let preferred: UUID?
  /// Advertisers that refused a preamble recently; not dialed.
  public let avoided: Set<UUID>
  /// Whether the link dials `preferred` alone, never another advertiser.
  public let isExclusive: Bool

  /// Dial `preferred` first and never one of `avoided`.
  public init(preferred: UUID? = nil, avoided: Set<UUID> = []) {
    self.preferred = preferred
    self.avoided = avoided
    isExclusive = false
  }

  private init(only peer: UUID) {
    preferred = peer
    avoided = []
    isExclusive = true
  }

  /// Dial `peer` and no other advertiser: a pairing search opens one
  /// connection to each peripheral it found (RAPP v26.11.8 §4.2, "Trying
  /// Each Custodian in Pairing Mode" item 1).
  public static func only(_ peer: UUID) -> Self {
    Self(only: peer)
  }
}
