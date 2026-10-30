// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine

/// The stream channel a custodian's pairing offer is served on.
///
/// The card holder listens and the requester
/// dials (RAPP discovery hierarchy §3.3). The holder publishes a fresh
/// random name carrying the pairing-mode attributes; the requester browses
/// for those attributes (``PairingCandidateLink``), because anything derived
/// from the code would let the network search for it.
internal final class PairingRelay: @unchecked Sendable {
  private let onEvent: @Sendable (PersistentRelayEvent) -> Void
  /// The `pairing-busy` for a requester arriving while another one is
  /// served (RAPP v26.10.29 §4.2, "Busy Refusal"); set before ``start()``.
  internal var busyAnswer: (@Sendable () -> Data?)?

  private var listener: StreamRelayListener?
  private var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
  private var reportedArrival = false

  /// Builds the channel the custodian's offer is served on.
  internal init(onEvent: @escaping @Sendable (PersistentRelayEvent) -> Void) {
    self.onEvent = onEvent
  }

  /// Opens the channel: the holder publishes and listens.
  internal func start() {
    // Only a phone holds the card and listens; a Mac is always the
    // requester and never accepts a connection (decisions 2026-10-10).
    #if os(iOS)
      let made = StreamRelayListener(
        busyAnswer: { [busyAnswer] first in
          first == rappStreamPairingPreamble() ? busyAnswer?() : nil
        },
        onEvent: { [weak self] event in self?.receiveStream(event) })
      listener = made
      made.start(
        displayName: StreamRendezvousName.ephemeralName(),
        txtRecord: StreamRendezvousName.pairingAttributes)
    #else
      onEvent(.closed(.startup("a Mac does not hold the card")))
    #endif
  }

  /// Hands one frame to the peer.
  internal func send(_ frame: Data) throws {
    guard let listener else { throw PersistentRelayTransportError.disconnected }
    try listener.send(frame)
  }

  /// Sends `frame` as the requester's last and ends its connection, keeping
  /// the listener and its published name for the next requester; false
  /// when the channel cannot.
  internal func endConnection(answering frame: Data) -> Bool {
    listener?.endConnection(answering: frame) ?? false
  }

  /// Closes the channel.
  internal func cancel() {
    listener?.cancel()
  }

  /// Reports a stream event the way the ceremony above names it.
  ///
  /// The requester has arrived once its pairing preamble is received
  /// (RAPP v26.10.29 §2.2.1 routing): anything else first is
  /// pre-authentication invalid input that closes that connection, and the
  /// offer keeps listening.
  private func receiveStream(_ event: StreamRelayEvent) {
    switch admission.admit(event) {
    case .ignore:
      return

    case .arrive:
      guard !reportedArrival else { return }
      reportedArrival = true
      onEvent(.connected)

    case .reject:
      listener?.disconnect()

    case .forward:
      if case .closed = event {
        // The next requester on this listener arrives afresh.
        reportedArrival = false
      }
      onEvent(PersistentRelayEvent(event))
    }
  }
}
