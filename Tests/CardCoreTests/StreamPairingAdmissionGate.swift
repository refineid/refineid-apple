// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// Applies an admission on the listener's queue, as the card holder does.
internal final class StreamPairingAdmissionGate: @unchecked Sendable {
  internal weak var listener: StreamRelayListener?
  private let lock = NSLock()
  private var admission: StreamPairingAdmission
  private var seen: [StreamPairingAdmission.Action] = []

  internal var actions: [StreamPairingAdmission.Action] {
    lock.withLock { seen }
  }

  internal init(preamble: Data) {
    admission = StreamPairingAdmission(preamble: preamble)
  }

  internal func receive(_ event: StreamRelayEvent) {
    let action = lock.withLock {
      let action = admission.admit(event)
      seen.append(action)
      return action
    }
    if action == .reject { listener?.disconnect() }
  }
}
