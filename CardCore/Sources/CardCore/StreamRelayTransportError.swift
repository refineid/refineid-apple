// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Why the stream channel ended.
public enum StreamRelayTransportError: Error, Equatable, Sendable {
  case cancelled
  case disconnected
  case invalidFrameLength
  /// No dial was opened: the platform denies this app the local network.
  case localNetworkDenied
  case malformedFrame
  case notConnected
  case send(String)
  case unreachable
}
