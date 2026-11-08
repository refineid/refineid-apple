// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// The endpoint a requester's pairing search opened last.
///
/// The search opens one connection at a time and ends with the one that
/// paired, so the last endpoint opened is the paired phone's route.
internal final class LastDialedEndpoint: Sendable {
  private let endpoint = OSAllocatedUnfairLock<PairingEndpoint?>(initialState: nil)

  /// The Bluetooth advertiser opened last; nil when the last connection
  /// went over the stream.
  internal var peripheral: UUID? {
    endpoint.withLock { opened in
      guard case .bluetooth(let peripheral) = opened else { return nil }
      return peripheral
    }
  }

  /// Notes that `opened` is being opened.
  internal func record(_ opened: PairingEndpoint) {
    endpoint.withLock { $0 = opened }
  }
}
