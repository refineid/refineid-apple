// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

#if REFINEID_STREAM_TRANSPORT
  import RappEngine
#endif

/// The channel a custodian's pairing offer is served on, whichever transport
/// carries it.
///
/// Pairing and the sessions that follow it have to travel the same way: a
/// pairing made over a transport the peers cannot use again is a pairing
/// they cannot use. This presents one shape so the ceremony does not know
/// which is underneath.
///
/// Over the stream transport the card holder listens and the requester
/// dials (RAPP discovery hierarchy §3.3). The holder publishes a fresh
/// random name carrying the pairing-mode attributes; the requester browses
/// for those attributes (``PairingCandidateLink``), because anything derived
/// from the code would let the network search for it.
internal final class PairingRelay: @unchecked Sendable {
  private let onEvent: @Sendable (PersistentRelayEvent) -> Void
  /// The `pairing-busy` for a requester arriving while another one is
  /// served (RAPP v26.10.29 §4.2, "Busy Refusal"); set before ``start()``.
  internal var busyAnswer: (@Sendable () -> Data?)?

  #if REFINEID_STREAM_TRANSPORT
    private var listener: StreamRelayListener?
    private var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
    private var reportedArrival = false
  #else
    private let session: PersistentRelaySession
  #endif

  /// Builds the channel the custodian's offer is served on.
  internal init(
    displayName: String,
    onEvent: @escaping @Sendable (PersistentRelayEvent) -> Void
  ) {
    self.onEvent = onEvent
    #if !REFINEID_STREAM_TRANSPORT
      self.session = PersistentRelaySession(
        role: .cardHolder,
        displayName: displayName,
        onEvent: onEvent
      )
    #endif
  }

  /// Opens the channel: the holder publishes and listens.
  internal func start() {
    #if REFINEID_STREAM_TRANSPORT
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
    #else
      session.start()
    #endif
  }

  /// Hands one frame to the peer.
  internal func send(_ frame: Data) throws {
    #if REFINEID_STREAM_TRANSPORT
      guard let listener else { throw PersistentRelayTransportError.disconnected }
      try listener.send(frame)
    #else
      try session.send(frame)
    #endif
  }

  /// Sends `frame` as the requester's last and ends its connection, keeping
  /// the listener and its published name for the next requester; false
  /// when the channel cannot.
  internal func endConnection(answering frame: Data) -> Bool {
    #if REFINEID_STREAM_TRANSPORT
      listener?.endConnection(answering: frame) ?? false
    #else
      false
    #endif
  }

  /// Closes the channel.
  internal func cancel() {
    #if REFINEID_STREAM_TRANSPORT
      listener?.cancel()
    #else
      session.cancel()
    #endif
  }

  #if REFINEID_STREAM_TRANSPORT
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
  #endif
}
