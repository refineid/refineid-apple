// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// Holds the custodians found while discovery gathers.
///
/// Once released it hands them on: those on the stream first, then those
/// over Bluetooth, each in the order found. After the release each is
/// handed on as it is found.
internal final class PairingEndpointGathering: Sendable {
  private struct State {
    var gathered: [PairingEndpoint] = []
    var released = false
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let handOn: @Sendable (PairingEndpoint) -> Void

  /// Gathering that hands each custodian on through `handOn`.
  internal init(handOn: @escaping @Sendable (PairingEndpoint) -> Void) {
    self.handOn = handOn
  }

  /// A custodian was found.
  internal func found(_ endpoint: PairingEndpoint) {
    state.withLock { state in
      guard state.released else {
        state.gathered.append(endpoint)
        return
      }
      handOn(endpoint)
    }
  }

  /// Ends the gathering: what was gathered is handed on, the stream first.
  ///
  /// Handing on happens under the lock, so nothing found meanwhile
  /// overtakes what was gathered.
  internal func release() {
    state.withLock { state in
      guard !state.released else { return }
      state.released = true
      let streamFirst =
        state.gathered.filter { if case .stream = $0 { true } else { false } }
        + state.gathered.filter { if case .bluetooth = $0 { true } else { false } }
      state.gathered.removeAll()
      for endpoint in streamFirst {
        handOn(endpoint)
      }
    }
  }
}
