// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

#if REFINEID_STREAM_TRANSPORT
  import Network
  import RappEngine
#endif

/// The channel a pairing ceremony runs over, whichever transport carries it.
///
/// Pairing and the sessions that follow it have to travel the same way: a
/// pairing made over a transport the peers cannot use again is a pairing
/// they cannot use. This presents one shape so the ceremony does not know
/// which is underneath.
///
/// Over the stream transport the card holder listens and the requester
/// dials (RAPP discovery hierarchy §3.3). The holder publishes a fresh
/// random name carrying the pairing-mode attributes; the requester browses
/// for those attributes, because anything derived from the code would let
/// the network search for it.
internal final class PairingRelay: @unchecked Sendable {
  private let onEvent: @Sendable (PersistentRelayEvent) -> Void

  #if REFINEID_STREAM_TRANSPORT
    private let role: PersistentRelayRole
    private var listener: StreamRelayListener?
    private var browser: StreamRelayBrowser?
    private var dialer: StreamRelaySession?
    private var reportedArrival = false
  #else
    private let session: PersistentRelaySession
  #endif

  /// Builds the channel one side of a ceremony speaks over.
  internal init(
    role: PersistentRelayRole,
    displayName: String,
    onEvent: @escaping @Sendable (PersistentRelayEvent) -> Void
  ) {
    self.onEvent = onEvent
    #if REFINEID_STREAM_TRANSPORT
      self.role = role
    #else
      self.session = PersistentRelaySession(
        role: role,
        displayName: displayName,
        onEvent: onEvent
      )
    #endif
  }

  /// Opens the channel: the holder publishes, the requester finds it.
  internal func start() {
    #if REFINEID_STREAM_TRANSPORT
      switch role {
      case .host:
        let found = StreamRelayBrowser(
          matchingAttributes: StreamRendezvousName.pairingAttributes
        ) { [weak self] endpoint in
          self?.dial(endpoint)
        }
        browser = found
        found.start()

      case .cardHolder:
        let made = StreamRelayListener { [weak self] event in
          self?.receiveStream(event)
        }
        listener = made
        made.start(
          displayName: StreamRendezvousName.ephemeralName(),
          txtRecord: StreamRendezvousName.pairingAttributes)
      }
    #else
      session.start()
    #endif
  }

  /// Hands one frame to the peer.
  internal func send(_ frame: Data) async throws {
    #if REFINEID_STREAM_TRANSPORT
      if let dialer {
        try await dialer.send(frame)
      } else if let listener {
        try listener.send(frame)
      } else {
        throw PersistentRelayTransportError.disconnected
      }
    #else
      try session.send(frame)
    #endif
  }

  /// Closes the channel.
  internal func cancel() {
    #if REFINEID_STREAM_TRANSPORT
      listener?.cancel()
      browser?.cancel()
      dialer?.cancel()
    #else
      session.cancel()
    #endif
  }

  #if REFINEID_STREAM_TRANSPORT
    /// Dials the holder once its published listener has been found.
    private func dial(_ endpoint: NWEndpoint) {
      guard dialer == nil else { return }
      let made = StreamRelaySession(
        service: endpoint,
        preamble: rappStreamPairingPreamble()
      ) { [weak self] event in
        self?.receiveStream(event)
      }
      dialer = made
      made.start()
    }

    /// Reports a stream event the way the ceremony above names it.
    ///
    /// The requester has arrived once its connection is open and its
    /// preamble sent. The holder waits for that preamble (RAPP v26.10.9
    /// §5.2 routing): anything else first is pre-authentication invalid
    /// input and drops the connection.
    private func receiveStream(_ event: StreamRelayEvent) {
      switch (role, event) {
      case (.host, .connected):
        reportArrival()

      case (.cardHolder, .connected):
        return

      case (.cardHolder, .frame(let payload)) where !reportedArrival:
        if payload == rappStreamPairingPreamble() {
          reportArrival()
        } else {
          listener?.cancel()
        }

      default:
        onEvent(PersistentRelayEvent(event))
      }
    }

    private func reportArrival() {
      guard !reportedArrival else { return }
      reportedArrival = true
      onEvent(.connected)
    }
  #endif
}
