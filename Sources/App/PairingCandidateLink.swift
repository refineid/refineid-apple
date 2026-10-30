// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// How a requester finds the custodians in pairing mode and opens pairing
/// connections to them (RAPP v26.10.29 §4.2, "Trying Each Custodian in
/// Pairing Mode").
internal enum PairingCandidateLink {
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
}
