// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One session over a stored pairing (RAPP v26.10.29 §6.3, §7.1 item 5).
///
/// The session authenticates the pairing's keys with `Noise_KK`, then the
/// custodian sends `session.ready` and the requester verifies it, and the
/// session carries operations until it closes. Closing spends the bridge.
public final class RappSessionBridge: @unchecked Sendable {
  /// Where the session has reached.
  private enum Phase {
    case handshaking(SessionHandshake)
    case authenticating(SessionAuthentication)
    case established(EstablishedSession)
    case closed
  }

  private let lock = NSLock()
  private let pair: RappPairRecord
  private var phase: Phase

  private init(pair: RappPairRecord, handshake: SessionHandshake) {
    self.pair = pair
    self.phase = .handshaking(handshake)
  }

  /// Opens a session as the requester, after an explicit local user action,
  /// bound to the connection's `transportProfile`.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` when the stored pairing is
  ///   not this endpoint's or the profile is unregistered,
  ///   ``RappBindingError/StorageUnconfirmed`` for a record the peer never
  ///   confirmed, and ``RappBindingError/ProtocolFailure`` when the
  ///   handshake cannot start.
  public static func beginRequester(
    pair: RappPairRecord, transportProfile: String
  ) throws -> RappSessionBridge {
    try mapping {
      RappSessionBridge(
        pair: pair,
        handshake: try SessionHandshake.beginRequester(
          pair: try pair.record, transportProfile: transportProfile, intent: ExplicitUserIntent()))
    }
  }

  /// Answers one incoming connection as the custodian, bound to the
  /// connection's `transportProfile`.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` when the stored pairing is
  ///   not this endpoint's or the profile is unregistered, and
  ///   ``RappBindingError/StorageUnconfirmed`` for a record the peer never
  ///   confirmed.
  public static func beginProxy(
    pair: RappPairRecord, transportProfile: String
  ) throws -> RappSessionBridge {
    try mapping {
      RappSessionBridge(
        pair: pair,
        handshake: try SessionHandshake.beginProxy(
          pair: try pair.record, transportProfile: transportProfile))
    }
  }

  /// Runs an engine step, naming its failure in the public vocabulary.
  private static func mapping<Value>(_ body: () throws -> Value) throws -> Value {
    do {
      return try body()
    } catch let error as RappBindingError {
      throw error
    } catch let error as SessionError {
      throw bindingError(error)
    } catch {
      throw RappBindingError.ProtocolFailure
    }
  }

  /// Names a session failure in the public vocabulary.
  private static func bindingError(_ error: SessionError) -> RappBindingError {
    switch error {
    case .roleViolation, .unregisteredTransport:
      .InvalidInput

    case .closed, .duplicateReady, .readyIncomplete:
      .WrongPhase

    case .storageUnconfirmed:
      .StorageUnconfirmed

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

  /// Moves from the handshake to `session.ready`: the custodian sends it,
  /// the requester verifies it.
  ///
  /// For a forgotten record, deliver ``deliverRevocationNotice()`` instead.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before the handshake finished.
  public func enterAuthentication() throws {
    try locked {
      guard case .handshaking(let handshake) = phase else { throw RappBindingError.WrongPhase }
      phase = .authenticating(try Self.mapping { try handshake.intoAuthentication() })
    }
  }

  /// Whether the pairing was forgotten locally, so the session's first and
  /// only message is the `pairing_revoked` close (§4.6 item 2).
  public func revocationNoticePending() -> Bool {
    pair.metadata().forgottenAtMs != nil
  }

  /// The custodian's `session.ready`: the exact session parameters with a
  /// fresh random nonce.
  ///
  /// Then call ``enterEstablished()``.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside authentication, on a
  /// requester, for a forgotten record, or on a second ready.
  public func sendReady(nonce: Data) throws -> Data {
    guard !revocationNoticePending() else { throw RappBindingError.WrongPhase }
    return try locked {
      guard case .authenticating(var authentication) = phase else {
        throw RappBindingError.WrongPhase
      }
      defer { phase = .authenticating(authentication) }
      return try Self.mapping { try authentication.sendReady(nonce: nonce) }
    }
  }

  /// The requester reads the custodian's first message (§7.1 item 5).
  ///
  /// On ``RappReadyOutcome/verified`` call ``enterEstablished()``; every other
  /// outcome ends the session. The pairing stays unless the custodian closed
  /// with `pairingRevoked`.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside authentication or on
  /// the custodian.
  public func receiveReady(bytes: Data) throws -> RappReadyOutcome {
    try locked {
      guard case .authenticating(var authentication) = phase else {
        throw RappBindingError.WrongPhase
      }
      let outcome: RappReadyOutcome
      do {
        outcome = try authentication.receiveReady(bytes)
      } catch {
        throw RappBindingError.WrongPhase
      }
      phase = outcome == .verified ? .authenticating(authentication) : .closed
      return outcome
    }
  }

  /// The first and only message of a session whose record was forgotten:
  /// the sealed `session.close` with reason `pairing_revoked` (§4.6 item
  /// 2), sent once ``enterAuthentication()`` ran and before anything else.
  ///
  /// The session closes and no card session starts; deliver the frame, drop
  /// the link, then destroy the record with
  /// ``RappPairRecord/revoke(vault:revokedAtMs:)``.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` outside authentication, after
  /// the custodian's `session.ready`, or for a record that is not
  /// forgotten.
  public func deliverRevocationNotice() throws -> Data {
    guard revocationNoticePending() else { throw RappBindingError.WrongPhase }
    return try locked {
      guard case .authenticating(var authentication) = phase else {
        throw RappBindingError.WrongPhase
      }
      phase = .closed
      return try Self.mapping { try authentication.sendRevocationNotice() }
    }
  }

  /// Promotes the session to healthy once the custodian sent, or the
  /// requester verified, `session.ready`.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` before that, or for a
  ///   forgotten record.
  public func enterEstablished() throws {
    guard !revocationNoticePending() else { throw RappBindingError.WrongPhase }
    try locked {
      guard case .authenticating(let authentication) = phase else {
        throw RappBindingError.WrongPhase
      }
      phase = .established(try Self.mapping { try authentication.intoEstablished() })
    }
  }

  /// Whether `session.ready` produced a healthy session.
  public func isEstablished() -> Bool {
    locked {
      guard case .established(let session) = phase else { return false }
      return session.isOpen
    }
  }

  /// Closes the session and spends the bridge; the pairing stays.
  public func closeSession() {
    locked { phase = .closed }
  }

  /// The established session, for the operation bridge built over it.
  internal func takeEstablished() throws -> (session: EstablishedSession, pair: PairRecord) {
    try locked {
      guard case .established(let session) = phase else { throw RappBindingError.WrongPhase }
      return (session, try pair.record)
    }
  }

  private func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
