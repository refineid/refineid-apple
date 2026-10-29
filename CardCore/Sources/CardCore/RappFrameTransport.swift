// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The sole byte-transport capability required by RAPP.
  ///
  /// Implementations must preserve frame boundaries and report successful
  /// release by returning from ``send(_:)``. They must not parse, log, retry,
  /// or reinterpret frames.
  public protocol RappFrameTransport: Sendable {
    func send(_ frame: Data) async throws
    func close() async
    /// Sends `frame` as the current connection's last and ends that
    /// connection, keeping the transport for the next one; false when the
    /// transport cannot, and then nothing was sent.
    func endConnection(answering frame: Data) async -> Bool
  }

  extension RappFrameTransport {
    /// A transport that carries one connection cannot outlive it.
    public func endConnection(answering _: Data) -> Bool {
      false
    }
  }
#endif
