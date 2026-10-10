// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One authenticated session over a stored pairing.
///
/// The session is ephemeral: it authenticates the pairing's keys, verifies
/// that both endpoints agree on the same parameters, and carries operations
/// until it closes. Closing spends the bridge.
public final class RappSessionBridge: @unchecked Sendable {
  /// Where the session has reached.
  private enum Phase {
    case handshaking(SessionHandshake)
    case authenticating(SessionAuthentication)
    case established(EstablishedSession)
    case closed
  }

  private let lock = NSLock()
  private let pairRecord: PairRecord
  private var phase: Phase

  private init(pairRecord: PairRecord, handshake: SessionHandshake) {
    self.pairRecord = pairRecord
    self.phase = .handshaking(handshake)
  }

  /// Opens a session as the requester, after an explicit local user action,
  /// bound to the connection's `transportProfile`.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` when the stored pairing is
  ///   not this endpoint's, and ``RappBindingError/ProtocolFailure`` when the
  ///   handshake cannot start.
  public static func beginRequester(
    pair: RappPairRecord,
    vault: RappOperationVault,
    transportProfile: String
  ) throws -> RappSessionBridge {
    _ = vault
    do {
      return RappSessionBridge(
        pairRecord: pair.record,
        handshake: try SessionHandshake.beginRequester(
          pair: pair.record, transportProfile: transportProfile, intent: ExplicitUserIntent()))
    } catch let error as SessionError {
      throw bindingError(error)
    } catch {
      throw RappBindingError.ProtocolFailure
    }
  }

  /// Answers one incoming connection as the proxy, bound to the
  /// connection's `transportProfile`.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` when the stored pairing is
  ///   not this endpoint's.
  public static func beginProxy(
    pair: RappPairRecord,
    vault: RappOperationVault,
    transportProfile: String
  ) throws -> RappSessionBridge {
    _ = vault
    do {
      return RappSessionBridge(
        pairRecord: pair.record,
        handshake: try SessionHandshake.beginProxy(
          pair: pair.record, transportProfile: transportProfile))
    } catch let error as SessionError {
      throw bindingError(error)
    } catch {
      throw RappBindingError.ProtocolFailure
    }
  }

  /// Runs an engine step, naming its failure in the public vocabulary.
  private static func mapping<Value>(_ body: () throws -> Value) throws -> Value {
    do {
      return try body()
    } catch let error as SessionError {
      throw bindingError(error)
    } catch {
      throw RappBindingError.ProtocolFailure
    }
  }

  /// Names a session failure in the public vocabulary.
  private static func bindingError(_ error: SessionError) -> RappBindingError {
    switch error {
    case .roleViolation:
      .InvalidInput

    case .closed:
      .WrongPhase

    default:
      .ProtocolFailure
    }
  }

  /// The next handshake frame for this role.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside the handshake.
  public func writeHandshakeFrame() throws -> Data {
    try locked {
      guard case .handshaking(var handshake) = phase else { throw RappBindingError.WrongPhase }
      defer { phase = .handshaking(handshake) }
      return try Self.mapping { try handshake.writeMessage() }
    }
  }

  /// Consumes one handshake frame from the peer.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the frame does not
  ///   verify.
  public func readHandshakeFrame(bytes: Data) throws {
    try locked {
      guard case .handshaking(var handshake) = phase else { throw RappBindingError.WrongPhase }
      defer { phase = .handshaking(handshake) }
      try Self.mapping { try handshake.readMessage(bytes) }
    }
  }

  /// Whether the handshake has finished.
  public func handshakeComplete() throws -> Bool {
    try locked {
      guard case .handshaking(let handshake) = phase else { throw RappBindingError.WrongPhase }
      return handshake.isComplete
    }
  }

  /// Moves from the handshake to mutual parameter verification.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before the handshake finished.
  public func enterAuthentication() throws {
    try locked {
      guard case .handshaking(let handshake) = phase else { throw RappBindingError.WrongPhase }
      phase = .authenticating(try Self.mapping { try handshake.intoAuthentication() })
    }
  }

  /// Sends this endpoint's parameter echo.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside authentication.
  public func sendReady(nonce: Data) throws -> Data {
    try locked {
      guard case .authenticating(var authentication) = phase else {
        throw RappBindingError.WrongPhase
      }
      defer { phase = .authenticating(authentication) }
      return try Self.mapping { try authentication.sendReady(nonce: nonce) }
    }
  }

  /// Verifies the peer's parameter echo.
  ///
  /// - Throws: ``RappBindingError/ProtocolFailure`` when the echo does not
  ///   match, which ends the pairing.
  public func receiveReady(bytes: Data, nowMs _: UInt64) throws {
    try locked {
      guard case .authenticating(var authentication) = phase else {
        throw RappBindingError.WrongPhase
      }
      defer { phase = .authenticating(authentication) }
      try Self.mapping { try authentication.receiveReady(bytes) }
    }
  }

  /// Declares the session healthy, after both echoes verified.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before both echoes arrived.
  public func enterEstablished() throws {
    try locked {
      guard case .authenticating(let authentication) = phase else {
        throw RappBindingError.WrongPhase
      }
      phase = .established(try Self.mapping { try authentication.intoEstablished() })
    }
  }

  /// Whether the session is healthy and may carry operations.
  public func isEstablished() -> Bool {
    locked {
      guard case .established(let session) = phase else { return false }
      return session.isOpen
    }
  }

  /// Closes the session and spends the bridge.
  public func closeSession() {
    locked { phase = .closed }
  }

  /// Seals one opaque payload over the established session.
  ///
  /// A caller that carries its own correlation and answers each request
  /// once needs the cipher and nothing above it: ordering and replay are
  /// already settled by the nonce this advances.
  ///
  /// - Parameter payload: the bytes to seal.
  /// - Returns: the frame to hand the transport.
  /// - Throws: ``RappBindingError/WrongPhase`` before the session is
  ///   established, and ``RappBindingError/ProtocolFailure`` if it cannot
  ///   be sealed.
  public func sealPayload(_ payload: Data) throws -> Data {
    try locked {
      guard case .established(var session) = phase else {
        throw RappBindingError.WrongPhase
      }
      do {
        let frame = try session.sealPayload(payload)
        phase = .established(session)
        return frame
      } catch {
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// Opens one opaque payload from the established session.
  ///
  /// A frame that will not open ends the session and leaves the pairing
  /// standing.
  ///
  /// - Parameter frame: the bytes the transport delivered.
  /// - Returns: the payload the peer sealed.
  /// - Throws: ``RappBindingError/WrongPhase`` before the session is
  ///   established, and ``RappBindingError/ProtocolFailure`` when the
  ///   frame does not open.
  public func openPayload(_ frame: Data) throws -> Data {
    try locked {
      guard case .established(var session) = phase else {
        throw RappBindingError.WrongPhase
      }
      do {
        let payload = try session.openPayload(frame)
        phase = .established(session)
        return payload
      } catch {
        phase = .closed
        throw RappBindingError.ProtocolFailure
      }
    }
  }

  /// The established session, for the operation bridge built over it.
  internal func takeEstablished() throws -> (session: EstablishedSession, pair: PairRecord) {
    try locked {
      guard case .established(let session) = phase else { throw RappBindingError.WrongPhase }
      return (session, pairRecord)
    }
  }

  private func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
