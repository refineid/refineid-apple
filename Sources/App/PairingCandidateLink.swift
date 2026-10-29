// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

#if !REFINEID_STREAM_TRANSPORT
  import os
#endif

/// How a requester finds the custodians in pairing mode and opens pairing
/// connections to them (RAPP v26.10.29 §4.2, "Trying Each Custodian in
/// Pairing Mode").
internal enum PairingCandidateLink {
  #if !REFINEID_STREAM_TRANSPORT
    /// How long the nearby peer framework is given to bring the custodian.
    private static let arrivalSeconds: UInt64 = 15

    private static var displayName: String {
      #if os(macOS)
        String(localized: "RefineID Mac")
      #else
        String(localized: "RefineID iPad")
      #endif
    }
  #endif

  #if REFINEID_STREAM_TRANSPORT
    /// Each published service carrying the pairing attributes, once, in
    /// the order found, until `stop` is called.
    internal static func discover() -> (
      found: AsyncStream<PairingEndpoint>, stop: @Sendable () -> Void
    ) {
      let (found, sink) = AsyncStream.makeStream(of: PairingEndpoint.self)
      let browser = StreamRelayBrowser(
        reportingEachWithAttributes: StreamRendezvousName.pairingAttributes
      ) { service in
        sink.yield(PairingEndpoint(service: service))
      }
      browser.start()
      return (
        found,
        {
          browser.cancel()
          sink.finish()
        }
      )
    }

    /// Dials the custodian's pairing listener.
    internal static func dial(_ endpoint: PairingEndpoint) -> RappPairingConnection {
      .stream(to: endpoint.service)
    }
  #else
    /// The one endpoint the nearby peer framework stands for.
    internal static func discover() -> (
      found: AsyncStream<PairingEndpoint>, stop: @Sendable () -> Void
    ) {
      let (found, sink) = AsyncStream.makeStream(of: PairingEndpoint.self)
      sink.yield(PairingEndpoint())
      return (found, { sink.finish() })
    }

    /// Waits for the custodian over the nearby peer framework, giving it
    /// up when it does not arrive in time.
    internal static func dial(_: PairingEndpoint) -> RappPairingConnection {
      let (events, sink) = AsyncStream.makeStream(of: RappPairingConnection.Event.self)
      let arrived = OSAllocatedUnfairLock(initialState: false)
      let session = PersistentRelaySession(
        role: .host, displayName: Self.displayName
      ) { event in
        switch event {
        case .closed:
          sink.yield(.closed)
          sink.finish()

        case .connected:
          arrived.withLock { $0 = true }
          sink.yield(.connected)

        case .frame(let frame):
          sink.yield(.frame(frame))
        }
      }
      session.start()
      Task {
        try? await Task.sleep(for: .seconds(arrivalSeconds))
        if !arrived.withLock({ $0 }) {
          session.cancel()
        }
      }
      return RappPairingConnection(
        transport: RappClosureFrameTransport(
          sender: { frame in try session.send(frame) },
          closer: { session.cancel() }),
        events: events)
    }
  #endif
}
