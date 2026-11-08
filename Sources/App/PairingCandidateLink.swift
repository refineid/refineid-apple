// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// How a requester finds the custodians in pairing mode and opens pairing
/// connections to them (RAPP v26.11.2 §4.2, "Trying Each Custodian in
/// Pairing Mode").
///
/// Custodians are found on every transport the requester dials sessions
/// over: the stream's `mode=pairing` records and, on a Mac, the RAPP
/// service's Bluetooth advertisements. The stream is
/// tried first (hierarchy specification §3): advertisers are reported once
/// the stream has had ``bluetoothHeadStartMilliseconds`` to be found, so a
/// phone reachable both ways pairs over the stream, and Bluetooth reaches
/// a phone with no shared network.
internal enum PairingCandidateLink {
  /// How long the stream's records are gathered before the first
  /// Bluetooth advertiser is reported.
  internal static let bluetoothHeadStartMilliseconds = 2_000

  /// Each custodian found, once, in the order reported, until `stop` is
  /// called; never the Bluetooth advertiser `sessionPeer`, which carries
  /// this requester's session.
  internal static func discover(skipping sessionPeer: UUID?) -> (
    found: AsyncStream<PairingEndpoint>, stop: @Sendable () -> Void
  ) {
    let (found, sink) = AsyncStream.makeStream(of: PairingEndpoint.self)
    let browser = StreamRelayBrowser(
      reportingEachWithAttributes: StreamRendezvousName.pairingAttributes
    ) { service in
      sink.yield(.stream(service))
    }
    let bluetoothFrom = ContinuousClock.now + .milliseconds(bluetoothHeadStartMilliseconds)
    let scanner = RappBleAppearanceWatcher { peripheral in
      guard peripheral != sessionPeer else { return }
      Task {
        try? await Task.sleep(until: bluetoothFrom, clock: .continuous)
        sink.yield(.bluetooth(peripheral))
      }
    }
    browser.start()
    // A requester looks over Bluetooth only where it dials its sessions
    // over Bluetooth.
    if PersistentTokenRegistry.dialsOverBluetooth {
      scanner.start()
    }
    return (
      found,
      {
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
