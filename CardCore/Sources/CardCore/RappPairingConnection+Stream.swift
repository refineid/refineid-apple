// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine) && canImport(Network)
  import Foundation
  import Network
  import RappEngine

  extension RappPairingConnection {
    /// Dials the pairing listener a custodian published, sending the
    /// stream's pairing preamble first (RAPP v26.10.29 §4.2).
    public static func stream(to service: NWEndpoint) -> Self {
      stream { onEvent in
        StreamRelaySession(
          service: service, preamble: rappStreamPairingPreamble(), onEvent: onEvent)
      }
    }

    /// Dials a pairing listener at its address literals.
    public static func stream(toAddresses literals: [String]) -> Self {
      stream { onEvent in
        StreamRelaySession(
          endpointLiterals: literals, preamble: rappStreamPairingPreamble(), onEvent: onEvent)
      }
    }

    private static func stream(
      _ dialer: (@escaping @Sendable (StreamRelayEvent) -> Void) -> StreamRelaySession
    ) -> Self {
      let (events, sink) = AsyncStream.makeStream(of: Event.self)
      let session = dialer { event in
        switch event {
        case .closed(.localNetworkDenied):
          sink.yield(.notOpened(.localNetworkDenied))
          sink.finish()

        case .closed(.unreachable):
          sink.yield(.notOpened(.noAnswer))
          sink.finish()

        case .closed:
          sink.yield(.closed)
          sink.finish()

        case .connected:
          sink.yield(.connected)

        case .frame(let frame):
          sink.yield(.frame(frame))
        }
      }
      session.start()
      return Self(
        transport: RappClosureFrameTransport(
          sender: { frame in try await session.send(frame) },
          closer: { session.cancel() }),
        events: events)
    }
  }
#endif
