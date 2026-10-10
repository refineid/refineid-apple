// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Takes a stored pairing to a session that carries payloads.
  ///
  /// Frames arriving before the session is established belong to the
  /// handshake and frames after it are payloads, which both sides can tell
  /// apart without a marker because the handshake is strictly ordered and
  /// neither side sends a payload before it ends.
  ///
  /// Nothing here suspends. A step that awaited partway through would let
  /// the next frame arrive while this one had the session half-moved, and
  /// the peer's first ready message would be read as a handshake message.
  public actor SignRelaySession {
    /// Which side of the pairing this session serves.
    public enum Role: Sendable {
      case requester
      case proxy
    }

    private let bridge: RappSessionBridge
    private let role: Role
    private var readySent = false
    private var authenticating = false

    /// Whether the session can carry payloads.
    public var isEstablished: Bool {
      bridge.isEstablished()
    }

    /// Begins a session over `pair`.
    ///
    /// - Parameters:
    ///   - role: which side of the pairing this is.
    ///   - pair: the stored pairing to establish over.
    ///   - vault: where the pairing's records live.
    ///   - transportProfile: the connection's transport profile, which the
    ///     session binds.
    /// - Throws: whatever the engine reports for an unusable pairing.
    public init(
      role: Role,
      pair: RappPairRecord,
      vault: RappOperationVault,
      transportProfile: String = rappStreamProfileName()
    ) throws {
      self.role = role
      self.bridge =
        switch role {
        case .requester:
          try RappSessionBridge.beginRequester(
            pair: pair, vault: vault, transportProfile: transportProfile)

        case .proxy:
          try RappSessionBridge.beginProxy(
            pair: pair, vault: vault, transportProfile: transportProfile)
        }
    }

    /// Opens the handshake, which only the requester begins.
    ///
    /// - Returns: the frames to send.
    /// - Throws: whatever the engine reports for a frame it cannot write.
    public func start() throws -> SignRelayStep {
      guard role == .requester else { return SignRelayStep() }
      return SignRelayStep(send: [try bridge.writeHandshakeFrame()])
    }

    /// Takes one frame from the peer.
    ///
    /// - Parameter frame: the bytes the transport delivered.
    /// - Returns: the frames to send, and the payload if this frame carried
    ///   one.
    /// - Throws: whatever the engine reports for a frame it cannot take.
    public func receive(_ frame: Data) throws -> SignRelayStep {
      if isEstablished {
        return SignRelayStep(payload: try bridge.openPayload(frame))
      }
      if authenticating {
        try bridge.receiveReady(bytes: frame, nowMs: 0)
        let ready = try readyFrames()
        try bridge.enterEstablished()
        return SignRelayStep(send: ready)
      }
      var outgoing: [Data] = []
      try bridge.readHandshakeFrame(bytes: frame)
      // A side that still owes the peer a handshake message writes it before
      // asking whether the handshake is done, because writing it is what
      // finishes it.
      if try !bridge.handshakeComplete() {
        outgoing.append(try bridge.writeHandshakeFrame())
      }
      if try bridge.handshakeComplete() {
        try bridge.enterAuthentication()
        authenticating = true
        outgoing.append(contentsOf: try readyFrames())
      }
      return SignRelayStep(send: outgoing)
    }

    /// Seals one payload for the peer.
    ///
    /// - Parameter payload: the bytes to seal.
    /// - Returns: the frame to hand the transport.
    /// - Throws: ``RappBindingError/WrongPhase`` before the session is
    ///   established.
    public func seal(_ payload: Data) throws -> Data {
      try bridge.sealPayload(payload)
    }

    private func readyFrames() throws -> [Data] {
      guard !readySent else { return [] }
      readySent = true
      return [try bridge.sendReady(nonce: try RappPlatformEntropy().sessionReadyNonce())]
    }
  }
#endif
