// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// How a requester finds the custodians in pairing mode and opens pairing
/// connections to them (RAPP v26.11.8 §4.2, "Trying Each Custodian in
/// Pairing Mode").
///
/// Custodians are found on every transport the requester dials sessions
/// over: the stream's `mode=pairing` records and, on a Mac, the RAPP
/// service's Bluetooth advertisements. Discovery first gathers for
/// ``gatherMilliseconds``, so a custodian that answers slowly or only over
/// Bluetooth is found with the code (item 1) before a fast refusal from
/// another one could end the search; the gathered ones are handed on with
/// the stream first (hierarchy specification §3), and later ones at once.
internal enum PairingCandidateLink {
  /// How long discovery gathers custodians before the first is tried.
  internal static let gatherMilliseconds = 3_000

  /// Each custodian found, once, in the order handed on, until `stop` is
  /// called; never the Bluetooth advertiser `sessionPeer`, which carries
  /// this requester's session.
  internal static func discover(skipping sessionPeer: UUID?) -> (
    found: AsyncStream<PairingEndpoint>, stop: @Sendable () -> Void
  ) {
    let (found, sink) = AsyncStream.makeStream(of: PairingEndpoint.self)
    let gathering = PairingEndpointGathering { endpoint in sink.yield(endpoint) }
    let browser = StreamRelayBrowser(
      reportingEachWithAttributes: StreamRendezvousName.pairingAttributes
    ) { service in
      gathering.found(.stream(service))
    }
    let scanner = RappBleAppearanceWatcher { peripheral in
      guard peripheral != sessionPeer else { return }
      gathering.found(.bluetooth(peripheral))
    }
    browser.start()
    // A requester looks over Bluetooth only where it dials its sessions
    // over Bluetooth.
    if PersistentTokenRegistry.dialsOverBluetooth {
      scanner.start()
    }
    let release = Task {
      try? await Task.sleep(for: .milliseconds(gatherMilliseconds))
      gathering.release()
    }
    return (
      found,
      {
        release.cancel()
        browser.cancel()
        scanner.cancel()
        sink.finish()
      }
    )
  }

  /// Opens a pairing connection to the custodian at `endpoint`.
  internal static func dial(_ endpoint: PairingEndpoint) -> RappPairingConnection {
    switch endpoint {
    case .stream(let service):
      .stream(to: service)

    case .bluetooth(let peripheral):
      .bluetooth(to: peripheral) { step in
        #if DEBUG
          if case .ended(let failure) = step, failure != .cancelled, failure != .disconnected {
            DevErrorLog.report("pairing over Bluetooth: \(step.line)", source: .app)
          }
        #endif
      }
    }
  }
}
