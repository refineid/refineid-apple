// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why the channel ended without an answer.
public enum PersistentRelayTransportError: Error, Sendable {
  case disconnected
  /// The channel never opened, and the platform denied this app the
  /// local network.
  case localNetworkDenied
  case startup(String)
}
