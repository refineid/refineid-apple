// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation

  /// Adapts an existing platform transport without giving it any RAPP semantic
  /// authority. The closures must preserve frame boundaries and return only after
  /// the frame was released to the underlying transport.
  public actor RappClosureFrameTransport: RappFrameTransport {
    /// Releases one complete frame to the underlying transport.
    public typealias Sender = @Sendable (Data) async throws -> Void
    /// Tears down the underlying transport.
    public typealias Closer = @Sendable () async -> Void
    /// Sends a frame as the current connection's last and ends that
    /// connection, keeping the transport; false when it cannot.
    public typealias ConnectionEnder = @Sendable (Data) async -> Bool

    private let sender: Sender
    private let closer: Closer
    private let connectionEnder: ConnectionEnder?
    private var isClosed = false

    /// Wraps the transport closures; without `connectionEnder` the transport
    /// carries one connection.
    public init(
      sender: @escaping Sender,
      closer: @escaping Closer,
      connectionEnder: ConnectionEnder? = nil
    ) {
      self.sender = sender
      self.closer = closer
      self.connectionEnder = connectionEnder
    }

    /// Forwards one frame, refusing to send after close.
    public func send(_ frame: Data) async throws {
      guard !isClosed else { throw CancellationError() }
      try await sender(frame)
    }

    /// Ends the current connection after `frame`, keeping the transport.
    public func endConnection(answering frame: Data) async -> Bool {
      guard !isClosed, let connectionEnder else { return false }
      return await connectionEnder(frame)
    }

    /// Closes once; later sends are refused and later closes do nothing.
    public func close() async {
      guard !isClosed else { return }
      isClosed = true
      await closer()
    }
  }
#endif
