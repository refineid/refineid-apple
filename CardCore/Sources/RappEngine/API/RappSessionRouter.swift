// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Routes first frames for one listener, remembering the routing nonces it
/// admitted so a replayed preamble is refused (RAPP v26.10.29 §2.2.1).
public final class RappSessionRouter: @unchecked Sendable {
  private let lock = NSLock()
  private var replay = RoutingReplayCache()

  /// A router with an empty replay memory, for one listener.
  public init() {
    // Nothing is routed yet, so nothing is remembered.
  }

  /// Where the connection whose first frame is `preamble` goes, among the
  /// non-revoked `records` this listener serves.
  public func route(
    transportProfile: String, preamble: Data, records: [RappPairRecord]
  ) -> RappRoute {
    switch try? RoutingPreamble.decode(preamble, profile: transportProfile) {
    case .pairing:
      return .pairing

    case .session(let routing):
      let keys = records.map { pair in (try? pair.record).flatMap(RoutingKey.init(record:)) }
      guard let index = RoutingKey.route(keys: keys, profile: transportProfile, routing: routing)
      else { return .refuse }
      let fresh = lock.withLock { replay.admit(routing.nonce) }
      return fresh ? .session(index: index) : .refuse

    case nil:
      return .refuse
    }
  }
}
