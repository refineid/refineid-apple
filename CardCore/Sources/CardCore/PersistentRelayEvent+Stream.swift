// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(Network)

  import Foundation

  extension PersistentRelayEvent {
    /// The same event, named the way the relay above the transport names it.
    ///
    /// The two transports report the same three things, so the layer above
    /// need not know which one carried them.
    public init(_ event: StreamRelayEvent) {
      switch event {
      case .connected:
        self = .connected

      case .frame(let payload):
        self = .frame(payload)

      case .closed(.localNetworkDenied):
        self = .closed(.localNetworkDenied)

      case .closed:
        self = .closed(.disconnected)
      }
    }
  }

#endif
