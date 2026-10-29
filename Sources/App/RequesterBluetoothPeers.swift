// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Which advertisers the requester's Bluetooth dials prefer and avoid
/// (STPA CC-53).
///
/// A RAPP advertisement names no pairing (RAPP v26.10.29 §4.1), so the
/// requester learns which advertiser is its phone only from a routed
/// preamble. It dials the one that routed last first; one that refused is
/// not dialed again within the window, so a room of other people's phones
/// does not keep a login waiting.
internal struct RequesterBluetoothPeers: Equatable, Sendable {
  /// How long a refusing advertiser is passed over, in seconds.
  private static let refusalWindowSeconds = 30

  /// How long a refusing advertiser is passed over.
  internal static var refusalWindow: Duration {
    .seconds(refusalWindowSeconds)
  }

  /// The advertiser that last routed the preamble.
  internal private(set) var preferred: UUID?

  /// When each advertiser last refused the preamble.
  private var refusedAt: [UUID: ContinuousClock.Instant] = [:]

  /// The advertiser routed the preamble: it is dialed first from now on.
  internal mutating func routed(_ peer: UUID) {
    preferred = peer
    refusedAt.removeValue(forKey: peer)
  }

  /// The advertiser refused the preamble at `instant`.
  internal mutating func refused(_ peer: UUID, at instant: ContinuousClock.Instant) {
    refusedAt[peer] = instant
    if preferred == peer { preferred = nil }
  }

  /// The peers a dial at `instant` prefers and avoids.
  internal func dialing(at instant: ContinuousClock.Instant) -> RappBleCentralPeers {
    let avoided = refusedAt.filter { _, refused in instant - refused < Self.refusalWindow }
    return RappBleCentralPeers(preferred: preferred, avoided: Set(avoided.keys))
  }
}
