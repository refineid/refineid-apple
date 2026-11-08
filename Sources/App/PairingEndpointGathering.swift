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
    let now = state.withLock { state -> Bool in
      guard !state.released else { return true }
      state.gathered.append(endpoint)
      return false
    }
    if now { handOn(endpoint) }
  }

  /// Ends the gathering: what was gathered is handed on, the stream first.
  internal func release() {
    let gathered = state.withLock { state -> [PairingEndpoint] in
      state.released = true
      defer { state.gathered.removeAll() }
      return state.gathered
    }
    let streamFirst =
      gathered.filter { if case .stream = $0 { true } else { false } }
      + gathered.filter { if case .bluetooth = $0 { true } else { false } }
    for endpoint in streamFirst {
      handOn(endpoint)
    }
  }
}
