// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import os

/// Which pairing connection a custodian's offer serves, across its
/// transports.
///
/// One offer is served on the stream listener and on the Bluetooth
/// server (RAPP v26.11.2 §4.2), and its ceremony runs on one connection at
/// a time. The first connection to arrive claims the offer; another,
/// on either transport, is answered busy until the claim is released
/// (§4.2, "Busy Refusal"). A claim is taken on the queue the connection
/// arrives on, so a Bluetooth link's CPace step 1 is admitted only on the
/// link that claimed the offer; it is released once the ceremony has
/// handled that connection's end.
internal final class PairingConnectionClaim: Sendable {
  /// One pairing connection.
  internal enum Connection: Hashable, Sendable {
    case stream
    case bluetooth(RappBleGattLink)
  }

  private let holder = OSAllocatedUnfairLock<Connection?>(initialState: nil)

  /// Claims the offer for `connection`; false while another holds it.
  internal func claim(_ connection: Connection) -> Bool {
    holder.withLock { held in
      guard held == nil || held == connection else { return false }
      held = connection
      return true
    }
  }

  /// Whether `connection` holds the offer.
  internal func holds(_ connection: Connection) -> Bool {
    holder.withLock { $0 == connection }
  }

  /// Releases the offer if `connection` holds it.
  internal func release(_ connection: Connection) {
    holder.withLock { held in
      if held == connection { held = nil }
    }
  }
}
